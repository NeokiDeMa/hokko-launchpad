#[test_only]
module launchpad::launchpad_tests {
    use access_control::access_control::{RoleCap, OwnerCap, SRoles};
    use launchpad::{
        launch_manager::{Self, Launch},
        launchpad::{Self, Launchpad},
        roles::{Self, Creator, ROLES, Admin}
    };
    use std::{debug::print, string::String, u64::pow};
    use sui::{
        clock::{Self, Clock},
        coin::{Self, Coin},
        package::Publisher,
        sui::SUI,
        test_scenario::{Self as scen, Scenario},
        test_utils::{assert_eq, destroy}
    };

    const Bob: address = @0x456;
    const Carol: address = @0x789;
    const Alice: address = @0x123;
    const Hokko: address = @0xabc;
    const HokkoAdmin: address = @0xdef;

    public struct LAUNCHPAD_TESTS has drop {}

    public struct Nft has key, store {
        id: UID,
        image: String,
        name: String,
    }

    #[test, expected_failure(abort_code = 113)]
    fun abort_when_exceeding_supply_mint_ended() {
        let (
            mut scen,
            publisher,
            mut clock,
            mut launchpad,
            mut launch,
            creator,
            owner_cap,
            admin_cap,
        ) = setup();
        let (policy, tp_cap) = sui::transfer_policy::new<Nft>(&publisher, scen.ctx());
        let mut coin = coin::mint_for_testing<SUI>(std::u64::pow(120, 9), scen.ctx());
        launchpad.approve_launch(&admin_cap, object::id(&launch), option::none());
        // Check initial phase
        assert_eq(
            launch.phase(&launchpad, &clock),
            launch_manager::not_started_phase_testing(),
        );

        // Move clock to public phase
        let new_timestamp = clock.timestamp_ms() + 2700;
        clock.set_for_testing(new_timestamp);
        scen.next_tx(Alice);

        assert_eq(
            launch.phase(&launchpad, &clock),
            launch_manager::public_phase_testing(),
        );

        let (nfts, payments) = create_nfts_and_payments(
            10,
            &mut coin,
            to_mist(4),
            &mut scen,
        );

        nfts.zip_do!(payments, |nft, payment| {
            launch_manager::mint_with_kiosk<Nft>(
                &mut launch,
                nft,
                payment,
                &policy,
                &clock,
                &mut launchpad,
                scen.ctx(),
            );
        });

        // Attempt to mint more than the supply
        let (nfts, payments) = create_nfts_and_payments(
            21,
            &mut coin,
            to_mist(4),
            &mut scen,
        );

        nfts.zip_do!(payments, |nft, payment| {
            launch_manager::mint_with_kiosk<Nft>(
                &mut launch,
                nft,
                payment,
                &policy,
                &clock,
                &mut launchpad,
                scen.ctx(),
            );
        });

        destroy(coin);
        destroy(policy);
        destroy(tp_cap);
        destroy(creator);
        destroy(launch);
        destroy(publisher);
        destroy(clock);
        destroy(launchpad);
        destroy(owner_cap);
        destroy(admin_cap);
        scen.end();
    }

    #[test, expected_failure(abort_code = 115)]
    fun revert_to_many_whitelists_mints() {
        let (
            mut scen,
            publisher,
            mut clock,
            mut launchpad,
            mut launch,
            creator,
            owner_cap,
            admin_cap,
        ) = setup();
        let (policy, tp_cap) = sui::transfer_policy::new<Nft>(&publisher, scen.ctx());
        let mut coin = coin::mint_for_testing<SUI>(to_mist(100), scen.ctx());

        launchpad.approve_launch(&admin_cap, object::id(&launch), option::none());
        // Check initial phase
        assert_eq(
            launch.phase(&launchpad, &clock),
            launch_manager::not_started_phase_testing(),
        );

        // Move clock to whitelist phase
        let new_timestamp = clock.timestamp_ms() + 10;
        clock.set_for_testing(new_timestamp);
        launch.update_whitelist(&creator, vector[Alice], vector[10]);
        scen.next_tx(Alice);

        assert_eq(
            launch.phase(&launchpad, &clock),
            launch_manager::whitelist_phase_testing(),
        );

        let (nfts, payments) = create_nfts_and_payments(
            11,
            &mut coin,
            to_mist(1),
            &mut scen,
        );
        nfts.zip_do!(payments, |nft, payment| {
            launch_manager::mint_with_kiosk<Nft>(
                &mut launch,
                nft,
                payment,
                &policy,
                &clock,
                &mut launchpad,
                scen.ctx(),
            );
        });

        destroy(coin);
        destroy(policy);
        destroy(tp_cap);
        destroy(creator);
        destroy(launch);
        destroy(publisher);
        destroy(clock);
        destroy(launchpad);
        destroy(owner_cap);
        destroy(admin_cap);
        scen.end();
    }

    #[test]
    fun test_mint_with_custom_fee() {
        let (
            mut scen,
            publisher,
            mut clock,
            mut launchpad,
            mut launch,
            creator,
            owner_cap,
            admin_cap,
        ) = setup();
        let (policy, tp_cap) = sui::transfer_policy::new<Nft>(&publisher, scen.ctx());
        let mut coin = coin::mint_for_testing<SUI>(to_mist(100), scen.ctx());

        launchpad.approve_launch(&admin_cap, object::id(&launch), option::none());

        launchpad.set_custom_fee(&admin_cap, object::id(&launch), 50);

        let custom_fee = launchpad.fee_percentage(object::id(&launch));
        print(&b"custom_fee: ".to_string());
        print(&custom_fee);

        launch.update_whitelist(&creator, vector[Alice], vector[16]);

        // Check initial phase
        assert_eq(
            launch.phase(&launchpad, &clock),
            launch_manager::not_started_phase_testing(),
        );

        // Move clock to whitelist phase
        let new_timestamp = clock.timestamp_ms() + 100;
        clock.set_for_testing(new_timestamp);
        scen.next_tx(Alice);
        assert_eq(
            launch.phase(&launchpad, &clock),
            launch_manager::whitelist_phase_testing(),
        );

        let (nfts, payments) = create_nfts_and_payments(
            10,
            &mut coin,
            to_mist(1),
            &mut scen,
        );

        nfts.zip_do!(payments, |nft, payment| {
            launch_manager::mint_with_kiosk<Nft>(
                &mut launch,
                nft,
                payment,
                &policy,
                &clock,
                &mut launchpad,
                scen.ctx(),
            );
        });

        scen.next_tx(Alice);

        let withdraw_amount = to_mist(1 * 10);
        let dot_five_percent = withdraw_amount * 995 / 1000;
        print(&b"dot_five_percent: ".to_string());
        print(&dot_five_percent);
        print(&b"withdraw_amount: ".to_string());
        print(&withdraw_amount);

        launch_manager::withdraw(&mut launch, &creator, scen.ctx());

        scen.next_tx(Alice);
        let alice_coin = scen.take_from_address<Coin<SUI>>(Alice);
        assert_eq(alice_coin.value(), dot_five_percent);

        // Check whitelist phase
        assert_eq(
            launch.phase(&launchpad, &clock),
            launch_manager::whitelist_phase_testing(),
        );
        // Withdraw from launchpad
        scen.next_tx(Hokko);
        launchpad.withdraw(&admin_cap, scen.ctx());
        scen.next_tx(Hokko);
        let launchpad_coin = scen.take_from_address<Coin<SUI>>(Hokko);
        assert_eq(launchpad_coin.value(), withdraw_amount - dot_five_percent);

        destroy(coin);
        destroy(launchpad_coin);
        destroy(alice_coin);
        destroy(tp_cap);
        destroy(policy);
        destroy(publisher);
        destroy(clock);
        destroy(launchpad);
        destroy(launch);
        destroy(creator);
        destroy(owner_cap);
        destroy(admin_cap);
        scen.end();
    }

    #[test]
    fun test_withdraw_from_launchpad() {
        let (
            mut scen,
            publisher,
            mut clock,
            mut launchpad,
            mut launch,
            creator,
            owner_cap,
            admin_cap,
        ) = setup();
        let (policy, tp_cap) = sui::transfer_policy::new<Nft>(&publisher, scen.ctx());
        let mut coin = coin::mint_for_testing<SUI>(to_mist(100), scen.ctx());

        launchpad.approve_launch(&admin_cap, object::id(&launch), option::none());
        launch.update_whitelist(&creator, vector[Alice], vector[16]);

        // Check initial phase
        assert_eq(
            launch.phase(&launchpad, &clock),
            launch_manager::not_started_phase_testing(),
        );

        // Move clock to whitelist phase
        let new_timestamp = clock.timestamp_ms() + 100;
        clock.set_for_testing(new_timestamp);
        scen.next_tx(Alice);
        assert_eq(
            launch.phase(&launchpad, &clock),
            launch_manager::whitelist_phase_testing(),
        );

        let (nfts, payments) = create_nfts_and_payments(
            10,
            &mut coin,
            to_mist(1),
            &mut scen,
        );
        nfts.zip_do!(payments, |nft, payment| {
            launch_manager::mint_with_kiosk<Nft>(
                &mut launch,
                nft,
                payment,
                &policy,
                &clock,
                &mut launchpad,
                scen.ctx(),
            );
        });

        scen.next_tx(Alice);

        let withdraw_amount = to_mist(1 * 10);
        let after_two_percent = withdraw_amount * 98 / 100;

        launch_manager::withdraw(&mut launch, &creator, scen.ctx());

        scen.next_tx(Alice);
        let alice_coin = scen.take_from_address<Coin<SUI>>(Alice);
        assert_eq(alice_coin.value(), after_two_percent);

        // Check whitelist phase
        assert_eq(
            launch.phase(&launchpad, &clock),
            launch_manager::whitelist_phase_testing(),
        );
        // Withdraw from launchpad
        scen.next_tx(Hokko);
        launchpad.withdraw(&admin_cap, scen.ctx());
        scen.next_tx(Hokko);
        let launchpad_coin = scen.take_from_address<Coin<SUI>>(Hokko);
        assert_eq(launchpad_coin.value(), withdraw_amount - after_two_percent);

        destroy(coin);
        destroy(launchpad_coin);
        destroy(alice_coin);
        destroy(tp_cap);
        destroy(policy);
        destroy(publisher);
        destroy(clock);
        destroy(launchpad);
        destroy(launch);
        destroy(creator);
        destroy(owner_cap);
        destroy(admin_cap);
        scen.end();
    }

    #[test]
    fun test_change_start_timestamp() {
        let (
            mut scen,
            publisher,
            clock,
            launchpad,
            mut launch,
            creator,
            owner_cap,
            admin_cap,
        ) = setup();
        let (policy, tp_cap) = sui::transfer_policy::new<Nft>(&publisher, scen.ctx());

        let start_timestamp_ms = clock.timestamp_ms() + 5000;
        let whitelist_start_timestamp_ms = clock.timestamp_ms() + 2000;
        let custom_start_timestamp_ms = clock.timestamp_ms() + 1000;

        launch_manager::set_start_timestamps(
            &mut launch,
            &launchpad,
            &creator,
            start_timestamp_ms,
            whitelist_start_timestamp_ms,
            custom_start_timestamp_ms,
            &clock,
        );
        scen.next_tx(Alice);

        let (new_w_ts, new_c_ts, new_ts) = launch.get_start_timestamp_ms();
        assert_eq(new_ts, start_timestamp_ms);
        assert_eq(new_w_ts, whitelist_start_timestamp_ms);
        assert_eq(new_c_ts, custom_start_timestamp_ms);

        destroy(tp_cap);
        destroy(policy);
        destroy(admin_cap);
        destroy(owner_cap);
        destroy(publisher);
        destroy(clock);
        destroy(launchpad);
        destroy(launch);
        destroy(creator);
        scen.end();
    }

    #[test]
    fun test_mint() {
        let (
            mut scen,
            publisher,
            mut clock,
            mut launchpad,
            mut launch,
            creator,
            owner_cap,
            admin_cap,
        ) = setup();
        let (policy, tp_cap) = sui::transfer_policy::new<Nft>(&publisher, scen.ctx());
        let mut coin = coin::mint_for_testing<SUI>(to_mist(100), scen.ctx());

        launchpad.approve_launch(&admin_cap, object::id(&launch), option::none());
        // Check initial phase
        assert_eq(
            launch.phase(&launchpad, &clock),
            launch_manager::not_started_phase_testing(),
        );

        // Move clock to whitelist phase
        let new_timestamp = clock.timestamp_ms() + 8;
        clock.set_for_testing(new_timestamp);
        scen.next_tx(Alice);

        let (nfts, payments) = create_nfts_and_payments(
            1,
            &mut coin,
            to_mist(1),
            &mut scen,
        );

        nfts.zip_do!(payments, |nft, payment| {
            launch_manager::mint_with_kiosk<Nft>(
                &mut launch,
                nft,
                payment,
                &policy,
                &clock,
                &mut launchpad,
                scen.ctx(),
            );
        });

        // Check whitelist phase
        assert_eq(
            launch.phase(&launchpad, &clock),
            launch_manager::whitelist_phase_testing(),
        );

        // Move clock to custom phase
        let new_timestamp = clock.timestamp_ms() + 1020;
        clock.set_for_testing(new_timestamp);
        scen.next_tx(Alice);
        let (nfts, payments) = create_nfts_and_payments(
            2,
            &mut coin,
            to_mist(2),
            &mut scen,
        );

        nfts.zip_do!(payments, |nft, payment| {
            launch_manager::mint_with_kiosk<Nft>(
                &mut launch,
                nft,
                payment,
                &policy,
                &clock,
                &mut launchpad,
                scen.ctx(),
            );
        });

        // Check custom phase
        assert_eq(launch.phase(&launchpad, &clock), launch_manager::custom_phase_testing());

        // Move clock to public phase
        let new_timestamp = clock.timestamp_ms() + 2040;
        clock.set_for_testing(new_timestamp);
        scen.next_tx(Alice);

        // Check public phase
        assert_eq(launch.phase(&launchpad, &clock), launch_manager::public_phase_testing());
        let (nfts, payments) = create_nfts_and_payments(
            3,
            &mut coin,
            to_mist(4),
            &mut scen,
        );
        nfts.zip_do!(payments, |nft, payment| {
            launch_manager::mint_with_kiosk<Nft>(
                &mut launch,
                nft,
                payment,
                &policy,
                &clock,
                &mut launchpad,
                scen.ctx(),
            );
        });

        destroy(coin);
        destroy(policy);
        destroy(tp_cap);
        destroy(creator);
        destroy(launch);
        destroy(publisher);
        destroy(clock);
        destroy(launchpad);
        destroy(admin_cap);
        destroy(owner_cap);
        scen.end();
    }
    //
    #[test]
    fun test_public_phase() {
        let (
            mut scen,
            publisher,
            mut clock,
            mut launchpad,
            launch,
            creator,
            owner_cap,
            admin_cap,
        ) = setup();

        launchpad.approve_launch(&admin_cap, object::id(&launch), option::none());

        let new_timestamp = clock.timestamp_ms() + 2060;
        // print(&new_timestamp);

        clock.set_for_testing(new_timestamp);
        scen.next_tx(Alice);

        assert_eq(launch.phase(&launchpad, &clock), launch_manager::public_phase_testing());

        destroy(creator);
        destroy(launch);
        destroy(publisher);
        destroy(clock);
        destroy(launchpad);
        destroy(owner_cap);
        destroy(admin_cap);
        scen.end();
    }
    #[test]
    fun test_custom_phase() {
        let (
            mut scen,
            publisher,
            mut clock,
            mut launchpad,
            launch,
            creator,
            owner_cap,
            admin_cap,
        ) = setup();

        launchpad.approve_launch(&admin_cap, object::id(&launch), option::none());

        let new_timestamp = clock.timestamp_ms() + 1010;
        // print(&new_timestamp);

        clock.set_for_testing(new_timestamp);
        scen.next_tx(Alice);

        assert_eq(launch.phase(&launchpad, &clock), launch_manager::custom_phase_testing());

        destroy(creator);
        destroy(launch);
        destroy(publisher);
        destroy(clock);
        destroy(launchpad);
        destroy(owner_cap);
        destroy(admin_cap);
        scen.end();
    }
    //
    #[test]
    fun test_whitelist_phase() {
        let (
            mut scen,
            publisher,
            mut clock,
            mut launchpad,
            launch,
            creator,
            owner_cap,
            admin_cap,
        ) = setup();

        launchpad.approve_launch(&admin_cap, object::id(&launch), option::none());

        let new_timestamp = clock.timestamp_ms() + 10;

        clock.set_for_testing(new_timestamp);
        scen.next_tx(Alice);
        // print(&clock.timestamp_ms());

        assert_eq(
            launch.phase(&launchpad, &clock),
            launch_manager::whitelist_phase_testing(),
        );

        destroy(creator);
        destroy(launch);
        destroy(publisher);
        destroy(clock);
        destroy(launchpad);
        destroy(owner_cap);
        destroy(admin_cap);
        scen.end();
    }
    //
    #[test]
    fun test_not_started_phase() {
        let (scen, publisher, clock, launchpad, launch, creator, owner_cap, admin_cap) = setup();

        assert_eq(
            launch.phase(&launchpad, &clock),
            launch_manager::not_started_phase_testing(),
        );

        assert_eq(
            launchpad.launch_state(object::id(&launch)),
            launchpad::pending_launch_state_testing(),
        );

        destroy(creator);
        destroy(launch);
        destroy(publisher);
        destroy(clock);
        destroy(launchpad);
        destroy(owner_cap);
        destroy(admin_cap);
        scen.end();
    }

    #[test]
    fun test_approved_phase() {
        let (
            scen,
            publisher,
            clock,
            mut launchpad,
            launch,
            creator,
            owner_cap,
            admin_cap,
        ) = setup();

        launchpad.approve_launch(&admin_cap, object::id(&launch), option::none());

        assert_eq(
            launch.phase(&launchpad, &clock),
            launch_manager::not_started_phase_testing(),
        );
        assert_eq(
            launchpad.launch_state(object::id(&launch)),
            launchpad.launch_status_appoved(),
        );

        destroy(creator);
        destroy(launch);
        destroy(publisher);
        destroy(clock);
        destroy(launchpad);
        destroy(owner_cap);
        destroy(admin_cap);
        scen.end();
    }

    #[test]
    fun test_rejected() {
        let (
            scen,
            publisher,
            clock,
            mut launchpad,
            launch,
            creator,
            owner_cap,
            admin_cap,
        ) = setup();

        launchpad.reject_launch(&admin_cap, object::id(&launch));

        assert_eq(
            launch.phase(&launchpad, &clock),
            launch_manager::not_started_phase_testing(),
        );
        assert_eq(
            launchpad.launch_state(object::id(&launch)),
            launchpad::rejected_launch_state_testing(),
        );

        destroy(creator);
        destroy(launch);
        destroy(publisher);
        destroy(clock);
        destroy(launchpad);
        destroy(owner_cap);
        destroy(admin_cap);
        scen.end();
    }

    #[test]
    fun test_pause_and_resume_launch() {
        let (
            scen,
            publisher,
            clock,
            mut launchpad,
            launch,
            creator,
            owner_cap,
            admin_cap,
        ) = setup();

        launchpad.approve_launch(&admin_cap, object::id(&launch), option::none());

        assert_eq(
            launch.phase(&launchpad, &clock),
            launch_manager::not_started_phase_testing(),
        );
        assert_eq(
            launchpad.launch_state(object::id(&launch)),
            launchpad.launch_status_appoved(),
        );

        // Pause the launch
        launchpad.pause_launch(&admin_cap, object::id(&launch));

        assert_eq(
            launch.phase(&launchpad, &clock),
            launch_manager::not_started_phase_testing(),
        );
        assert_eq(
            launchpad.launch_state(object::id(&launch)),
            launchpad::paused_launch_state_testing(),
        );

        launchpad.resume_launch(&admin_cap, object::id(&launch));
        assert_eq(
            launch.phase(&launchpad, &clock),
            launch_manager::not_started_phase_testing(),
        );
        assert_eq(
            launchpad.launch_state(object::id(&launch)),
            launchpad.launch_status_appoved(),
        );

        destroy(creator);
        destroy(launch);
        destroy(publisher);
        destroy(clock);
        destroy(launchpad);
        destroy(owner_cap);
        destroy(admin_cap);
        scen.end();
    }

    //
    // #[test]
    // fun test_update_whitelist_logic() {
    //     let mut scen = scen::begin(Alice);
    //
    //     let allocations: vector<u64> = vector[1, 2, 3];
    //     let addresses = vector[Bob, Carol, Alice];
    //     let mut table = table::new<address, u64>(scen.ctx());
    //     let is_valid_allocations = allocations.all!(|allocation| {
    //         *allocation > 0
    //     });
    //
    //     assert!(is_valid_allocations);
    //
    //     addresses.zip_do!(allocations, |address, allocate| {
    //         table.add(address, allocate);
    //     });
    //
    //     // let carol_allocation = table.borrow(Carol);
    //
    //     assert_eq(*table.borrow(Carol), 2);
    //     assert_eq(*table.borrow(Alice), 3);
    //
    //     destroy(table);
    //     scen.end();
    // }

    //
    // #[test]
    // fun test_store_in_kioks() {
    //     let mut scen = scen::begin(Alice);
    //     let (mut kiosk, k_cap) = kiosk::new(scen.ctx());
    //
    //     let new_nft = Nft {
    //         id: object::new(scen.ctx()),
    //         image: b"example_image.png".to_string(),
    //         name: b"exampl nft".to_string(),
    //     };
    //     kiosk.place(&k_cap, new_nft);
    //     // kiosk.lock(&k_cap, _policy, item)
    //
    //     let pc = personal_kiosk::new(&mut kiosk, k_cap, scen.ctx());
    //     pc.transfer_to_sender(scen.ctx());
    //
    //     transfer::public_share_object(kiosk);
    //
    //     scen.end();
    // }
    //
    fun create_nfts_and_payments(
        amount_nfts: u64,
        coin: &mut Coin<SUI>,
        amount_coins: u64,
        scen: &mut Scenario,
    ): (vector<Nft>, vector<Coin<SUI>>) {
        let mut nfts: vector<Nft> = vector::empty<Nft>();
        let mut payments: vector<Coin<SUI>> = vector::empty<Coin<SUI>>();
        while (nfts.length() < amount_nfts) {
            let nft = Nft {
                id: object::new(scen.ctx()),
                image: b"example_image.png".to_string(),
                name: b"example nft".to_string(),
            };
            let payment = coin.split(amount_coins, scen.ctx());
            payments.push_back(payment);
            nfts.push_back(nft);
        };
        (nfts, payments)
    }

    //
    fun setup_launchpad(
        launchpad: &mut Launchpad,
        publisher: &Publisher,
        clock: &Clock,
        scen: &mut Scenario,
    ) {
        assert!(scen.ctx().sender() == Alice);
        let name = b"test launchpad".to_string();
        let description = b"test launchpad description".to_string();
        let supply = 30;
        let price = to_mist(4);
        let cover_url = b"http://".to_string();

        let is_kiosk = true;

        let max_items_per_address = 30;

        let whitelist_price = option::some(to_mist(1));
        let whitelist_supply = option::some(16);
        let whitelist_start_timestamp_ms = option::some(clock.timestamp_ms() + 3);
        // print(&whitelist_start_timestamp_ms.destroy_some());

        let custom_name = option::some(b"custom launchpad name".to_string());
        let custom_price = option::some(to_mist(2));
        let custom_supply = option::some(16);
        let custom_start_timestamp_ms = option::some(clock.timestamp_ms() + 1000);
        // print(&b"custom_start_timestamp_ms in setup test: ".to_string());
        // print(&custom_start_timestamp_ms.destroy_some());
        let start_timestamp_ms = clock.timestamp_ms() + 2000;

        launch_manager::new<Nft>(
            launchpad,
            publisher,
            clock,
            name,
            cover_url,
            description,
            supply,
            price,
            is_kiosk,
            start_timestamp_ms,
            max_items_per_address,
            whitelist_price,
            whitelist_supply,
            whitelist_start_timestamp_ms,
            custom_name,
            custom_price,
            custom_supply,
            custom_start_timestamp_ms,
            scen.ctx(),
        );

        scen.next_tx(Alice);
    }

    fun setup_whitelist(launch: &mut Launch, creator: &Creator) {
        let addresses = vector[Bob, Carol, Alice];
        let allocations = vector[4, 8, 9];

        launch_manager::update_whitelist(launch, creator, addresses, allocations);
    }

    fun setup(): (
        Scenario,
        Publisher,
        Clock,
        Launchpad,
        Launch,
        Creator,
        OwnerCap<ROLES>,
        RoleCap<Admin>,
    ) {
        let mut scen = scen::begin(Hokko);
        launchpad::test_init(scen.ctx());
        let package = sui::package::claim(LAUNCHPAD_TESTS {}, scen.ctx());
        let clock = clock::create_for_testing(scen.ctx());
        roles::test_init(scen.ctx());
        scen.next_tx(Alice);

        let mut launchpad = scen.take_shared<Launchpad>();
        let owner_cap = scen.take_from_address<OwnerCap<ROLES>>(Hokko);
        let mut s_roles = scen.take_shared<SRoles<ROLES>>();
        scen.next_tx(Hokko);
        roles::add_admin(&owner_cap, &mut s_roles, HokkoAdmin, scen.ctx());
        scen.next_tx(Alice);

        let admin_cap = scen.take_from_address<RoleCap<Admin>>(HokkoAdmin);

        setup_launchpad(&mut launchpad, &package, &clock, &mut scen);
        let mut launch = scen.take_shared<Launch>();
        let creator = scen.take_from_address<Creator>(Alice);
        setup_whitelist(&mut launch, &creator);

        destroy(s_roles);

        (scen, package, clock, launchpad, launch, creator, owner_cap, admin_cap)
    }

    //
    fun to_mist(amount: u64): u64 {
        amount * pow(10, 9)
    }
}

// #[test, expected_failure(abort_code = ::launchpad::launchpad_tests::ENotImplemented)]
// fun test_launchpad_fail() {
//     abort ENotImplemented
// }
