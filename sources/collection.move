module launchpad::collection_manager {
    use auth_bridge::authentication::Authentication;
    use kiosk::{kiosk_lock_rule, personal_kiosk as p_kiosk};
    use launchpad::{
        error,
        launchpad::Launchpad,
        roles::{Self, Creator},
        utils::{type_to_string, withdraw_balance, payment_split_fee}
    };
    use std::string::String;
    use sui::{
        balance::{Self, Balance},
        clock::Clock,
        coin::{Self, Coin},
        event::emit,
        kiosk,
        package::{Self, Publisher},
        sui::SUI,
        table::{Self, Table},
        transfer_policy::{TransferPolicy, has_rule, TransferPolicyCap}
    };

    // === Constants ===

    // === Structs ===

    public enum CollectionPhase has copy, drop, store {
        NotStarted,
        Whitelist,
        Custom,
        Public,
        Ended,
    }

    public struct Collection has key, store {
        id: UID,
        is_paused: bool,
        name: String,
        cover_url: String,
        description: String,
        supply: u64,
        /// The price per nft in the collection.
        /// The price is in MIST. E.g. 1_000_000_000 MIST (= 1 SUI).
        price: u64,
        /// Flag to determine if the collection uses a kiosk.
        /// If true, the mint uses kiosk lock rule, nft sent to user's kiosk.
        /// If false, nfts sent directly to the user.
        is_kiosk: bool,
        /// The time when the collection is available for minting.
        /// Can be set only after the collection is initialized and approved.
        start_timestamp_ms: u64,
        // === Item Type ===
        /// The type of the nft object.
        /// When the type is set, the collection will only accept nfts of this type.
        item_type: String,
        items: Table<ID, bool>,
        // === Items per address ===
        max_items_per_address: u64,
        items_per_address: Table<address, u64>,
        // === Treasury ===
        balance: Balance<SUI>,
        // === Whitelist ===
        whitelist_enabled: bool,
        /// The time when the whitelist phase starts.
        /// Can be set only after the collection is initialized and approved.
        /// Can't be more than the start timestamp of the collection.
        whitelist_start_timestamp_ms: u64,
        /// Whitelist. Represents the table with key as user address and value as the allocation.
        whitelist: Table<address, u64>,
        whitelist_price: u64,
        whitelist_supply: u64,
        // === Custom  Phase ===
        custom_enabled: bool,
        custom_name: String,
        custom_start_timestamp_ms: u64,
        custom_price: u64,
        custom_supply: u64,
    }

    // === Events ===

    // public struct CollectionCreated has copy, drop (ID)

    public struct CollectionTimestampsUpdatedEvent has copy, drop {
        collection: ID,
        whitelist_start_timestamp_ms: u64,
        custom_start_timestamp_ms: u64,
        start_timestamp_ms: u64,
    }

    public struct CollectionWhitelistUpdatedEvent has copy, drop {
        collection: ID,
        addresses: vector<address>,
        allocations: vector<u64>,
    }

    public struct CollectionPausedEvent has copy, drop (ID)

    public struct CollectionInitializedEvent has copy, drop {
        collection: ID,
        cover_url: String,
        item_type: String,
        is_kiosk: bool,
        name: String,
        description: String,
        supply: u64,
        price: u64,
        max_items_per_address: u64,
        start_timestamp_ms: u64,
        whitelist_enabled: bool,
        whitelist_start_timestamp_ms: u64,
        whitelist_price: u64,
        whitelist_supply: u64,
        custom_enabled: bool,
        custom_name: String,
        custom_start_timestamp_ms: u64,
        custom_price: u64,
        custom_supply: u64,
    }

    public struct CollectionResumedEvent has copy, drop (ID)

    public struct ItemMintedEvent has copy, drop {
        collection: ID,
        item: ID,
        address: address,
    }
    // === Init ===

    // === Public Functions ===

    #[allow(lint(self_transfer))]
    public fun new_with_kiosk<T: key + store>(
        launchpad: &mut Launchpad,
        publisher: &Publisher,
        clock: &Clock,
        name: String,
        cover_image: String,
        description: String,
        supply: u64,
        price: u64,
        policy: &mut TransferPolicy<T>,
        policy_cap: &TransferPolicyCap<T>,
        start_timestamp_ms: u64,
        max_items_per_address: u64,
        whitelist_price: Option<u64>,
        whitelist_supply: Option<u64>,
        whitelist_start_timestamp_ms: Option<u64>,
        custom_name: Option<String>,
        custom_price: Option<u64>,
        custom_supply: Option<u64>,
        custom_start_timestamp_ms: Option<u64>,
        ctx: &mut TxContext,
    ) {
        new<T>(
            launchpad,
            publisher,
            clock,
            name,
            cover_image,
            description,
            supply,
            price,
            true,
            start_timestamp_ms,
            max_items_per_address,
            whitelist_price,
            whitelist_supply,
            whitelist_start_timestamp_ms,
            custom_name,
            custom_price,
            custom_supply,
            custom_start_timestamp_ms,
            ctx,
        );

        create_policy_impl<T>(policy, policy_cap);
    }

    /// Create a new Collection. Shares Collection object and send Creator object to the sender.
    /// Sends collection to launchpad for approval.
    /// If `is_kiosk` is true, also creates a shared object TransferPolicy<T>, and TranferPolicyCap to manage it
    /// If `whitelist_price`, `whitelist_supply`, and `whitelist_start_timestamp_ms` are set,
    /// whitelist phase is enabled.
    #[allow(lint(self_transfer))]
    public fun new<T: key + store>(
        launchpad: &mut Launchpad,
        publisher: &Publisher,
        clock: &Clock,
        name: String,
        cover_url: String,
        description: String,
        supply: u64,
        price: u64,
        is_kiosk: bool,
        start_timestamp_ms: u64,
        max_items_per_address: u64,
        // Optional fields. Use option::some to set them or option::none to skip them
        // By default whitelist is disabled
        // To enable whitelist, set whitelist_price, whitelist_supply, and whitelist_start_timestamp_ms
        whitelist_price: Option<u64>,
        whitelist_supply: Option<u64>,
        whitelist_start_timestamp_ms: Option<u64>,
        // Optional fields. Use option::some to set them or option::none to skip them
        // By default custom phase is disabled
        // To enable custom phase, set custom_price, custom_supply, and custom_start_timestamp_ms
        custom_name: Option<String>,
        custom_price: Option<u64>,
        custom_supply: Option<u64>,
        custom_start_timestamp_ms: Option<u64>,
        ctx: &mut TxContext,
    ) {
        launchpad.assert_version();
        assert!(package::from_package<T>(publisher), error::invalidPublisher!());
        assert!(start_timestamp_ms >= clock.timestamp_ms(), error::invalidStartTimestamp!());

        let mut collection = Collection {
            id: object::new(ctx),
            is_paused: false,
            name,
            cover_url,
            description,
            supply,
            price,
            is_kiosk,
            start_timestamp_ms,
            balance: balance::zero(),
            item_type: type_to_string<T>(),
            items: table::new(ctx),
            max_items_per_address,
            items_per_address: table::new(ctx),
            whitelist_enabled: false,
            whitelist_start_timestamp_ms: 0,
            whitelist: table::new(ctx),
            whitelist_price: 0,
            whitelist_supply: 0,
            custom_enabled: false,
            custom_name: b"".to_string(),
            custom_start_timestamp_ms: 0,
            custom_price: 0,
            custom_supply: 0,
        };
        let creator = roles::new_creator(collection.id.to_inner(), ctx);

        if (
            whitelist_price.is_some() && 
            whitelist_supply.is_some() && 
            whitelist_start_timestamp_ms.is_some()
        ) {
            collection.enable_whitelist_impl(
                *whitelist_price.borrow(),
                *whitelist_supply.borrow(),
                *whitelist_start_timestamp_ms.borrow(),
                clock,
            );
        };

        if (
            custom_name.is_some() && 
            custom_price.is_some() && 
            custom_supply.is_some() && 
            custom_start_timestamp_ms.is_some()
        ) {
            let start_time = if (collection.whitelist_enabled) {
                *whitelist_start_timestamp_ms.borrow()
            } else {
                0
            };

            collection.enable_custom_impl(
                *custom_name.borrow(),
                *custom_price.borrow(),
                *custom_supply.borrow(),
                start_time + *custom_start_timestamp_ms.borrow(),
                clock,
            );
        };

        emit(CollectionInitializedEvent {
            collection: collection.id.to_inner(),
            cover_url,
            item_type: collection.item_type,
            is_kiosk: collection.is_kiosk,
            name: collection.name,
            description: collection.description,
            supply: collection.supply,
            price: collection.price,
            max_items_per_address: collection.max_items_per_address,
            start_timestamp_ms: collection.start_timestamp_ms,
            whitelist_enabled: collection.whitelist_enabled,
            whitelist_start_timestamp_ms: collection.whitelist_start_timestamp_ms,
            whitelist_price: collection.whitelist_price,
            whitelist_supply: collection.whitelist_supply,
            custom_enabled: collection.custom_enabled,
            custom_name: collection.custom_name,
            custom_start_timestamp_ms: collection.custom_start_timestamp_ms,
            custom_price: collection.custom_price,
            custom_supply: collection.custom_supply,
        });

        launchpad.register_collection(collection.id.to_inner(), collection.item_type);
        transfer::share_object(collection);
        transfer::public_transfer(creator, ctx.sender());
    }

    public fun mint_with_kiosk<T: key + store>(
        collection: &mut Collection,
        item: T,
        payment: Coin<SUI>,
        policy: &TransferPolicy<T>,
        clock: &Clock,
        launchpad: &mut Launchpad,
        ctx: &mut TxContext,
    ) {
        launchpad.assert_version();
        collection.assert_kiosk_enabled();
        let sender = ctx.sender();
        let (mut kiosk, cap) = kiosk::new(ctx);
        collection.mint_impl(launchpad, &item, payment, clock, ctx);
        kiosk.lock(&cap, policy, item);

        p_kiosk::create_for(&mut kiosk, cap, sender, ctx);
        transfer::public_share_object(kiosk);
    }

    public fun auth_mint_with_kiosk<T: key + store, K: key + store>(
        collection: &mut Collection,
        items: vector<T>,
        payments: vector<Coin<SUI>>,
        policy: &TransferPolicy<T>,
        clock: &Clock,
        launchpad: &mut Launchpad,
        auth: &Authentication<K>,
        ctx: &mut TxContext,
    ) {
        launchpad.assert_version();
        collection.assert_kiosk_enabled();
        let sender = ctx.sender();
        assert!(auth.get_initiator() == sender, error::wrongAddress!());

        assert!(
            auth.get_one_output(&b"amount".to_string()) == &items.length().to_string(),
            error::exceededMintAmount!(),
        );

        let (mut kiosk, cap) = kiosk::new(ctx);
        items.zip_do!(payments, |item, payment| {
            collection.mint_impl(launchpad, &item, payment, clock, ctx);
            kiosk.lock(&cap, policy, item);
        });

        p_kiosk::create_for(&mut kiosk, cap, sender, ctx);
        transfer::public_share_object(kiosk);
    }

    // === View Functions ===

    public fun phase(
        collection: &Collection,
        launchpad: &Launchpad,
        clock: &Clock,
    ): CollectionPhase {
        launchpad.assert_version();
        if (
            launchpad.collection_state(collection.id.to_inner()) != launchpad.collection_status_appoved()
        ) {
            return CollectionPhase::NotStarted
        };

        let now = clock.timestamp_ms();

        if (
            collection.whitelist_enabled && // true
                 now > collection.whitelist_start_timestamp_ms &&  // 0 >= 5, 1001 > 5 == true
                 now < collection.start_timestamp_ms // 1001 < 2000 == true
        ) {
            if (
                collection.custom_enabled && // true
               now > collection.custom_start_timestamp_ms && // 1001 > 1002 == false
                 now < collection.start_timestamp_ms // 1001 < 2000 == true
            ) {
                return CollectionPhase::Custom
            };

            return CollectionPhase::Whitelist
        };

        if (
            collection.custom_enabled && 
                 now > collection.custom_start_timestamp_ms &&
                 now < collection.start_timestamp_ms
        ) {
            return CollectionPhase::Custom
        };

        if (now < collection.start_timestamp_ms) {
            return CollectionPhase::NotStarted
        };

        if (
            now >= collection.start_timestamp_ms &&
                 collection.items.length() < collection.supply
        ) {
            return CollectionPhase::Public
        } else if (collection.items.length() >= collection.supply) {
            return CollectionPhase::Ended
        };
        return CollectionPhase::Ended
    }

    // === Admin(Creator Role) Functions ===

    /// @dev Optional function to change the start timestamps of the collection.
    /// @param whitelist_start_timestamp_ms Pass 0 for whitelist_start_timestamp_ms if whitelist is not enabled.
    /// @param custom_start_timestamp_ms Pass 0 for custom_start_timestamp_ms if custom is not enabled.
    /// Can be called after the collection is initialized.
    /// Can be called if for example Admin approved collection later than expected.
    public fun set_start_timestamps(
        collection: &mut Collection,
        launchpad: &Launchpad,
        cap: &Creator,
        start_timestamp_ms: u64,
        whitelist_start_timestamp_ms: u64,
        custom_start_timestamp_ms: u64,
        clock: &Clock,
    ) {
        cap.assert_collection_creator(collection.id.to_inner());
        assert!(collection.phase(launchpad, clock) != CollectionPhase::Ended, error::mintEnded!());
        assert!(start_timestamp_ms >= clock.timestamp_ms(), error::invalidStartTimestamp!());

        if (collection.whitelist_enabled) {
            assert!(
                whitelist_start_timestamp_ms >= clock.timestamp_ms(),
                error::invalidStartTimestamp!(),
            );
            assert!(
                whitelist_start_timestamp_ms < start_timestamp_ms,
                error::publicStartBeforeWhitelist!(),
            );
        };

        if (collection.custom_enabled) {
            assert!(
                custom_start_timestamp_ms >= clock.timestamp_ms(),
                error::invalidStartTimestamp!(),
            );
            assert!(
                custom_start_timestamp_ms < start_timestamp_ms,
                error::publicStartBeforeCustom!(),
            );
        };

        collection.start_timestamp_ms = start_timestamp_ms;
        collection.whitelist_start_timestamp_ms = whitelist_start_timestamp_ms;
        collection.custom_start_timestamp_ms = custom_start_timestamp_ms;

        emit(CollectionTimestampsUpdatedEvent {
            collection: collection.id.to_inner(),
            whitelist_start_timestamp_ms,
            custom_start_timestamp_ms,
            start_timestamp_ms,
        });
    }

    /// If whitelist is enabled, add addresses and allocations to the whitelist.
    public fun update_whitelist(
        collection: &mut Collection,
        cap: &Creator,
        addresses: vector<address>,
        allocations: vector<u64>,
    ) {
        // todo: add max batch size
        cap.assert_collection_creator(collection.id.to_inner());
        collection.assert_whitelist_enabled();

        let users_length = addresses.length();

        assert!(users_length >= 1, error::invalidVectorLength!());
        assert!(users_length == allocations.length(), error::invalidVectorLength!());

        let is_valid_allocations = allocations.all!(|allocation| {
            *allocation >= 1
        });

        assert!(is_valid_allocations, error::invalidWhitelistAllocation!());

        let whitelist = &mut collection.whitelist;

        addresses.zip_do!(allocations, |address, allocation| {
            if (!whitelist.contains(address)) {
                whitelist.add(address, allocation);
            } else {
                let current_allocation = &mut whitelist[address];
                *current_allocation = allocation;
            }
        });

        emit(CollectionWhitelistUpdatedEvent {
            collection: collection.id.to_inner(),
            addresses,
            allocations,
        });
    }

    /// Optional function to pause the collection.
    public fun pause(collection: &mut Collection, cap: &Creator) {
        cap.assert_collection_creator(collection.id.to_inner());
        collection.assert_not_paused();

        emit(
            CollectionPausedEvent(collection.id.to_inner()),
        );

        collection.is_paused = true;
    }

    /// If paused, resume the collection.
    public fun resume(collection: &mut Collection, cap: &Creator) {
        cap.assert_collection_creator(collection.id.to_inner());
        collection.assert_paused();

        emit(
            CollectionResumedEvent(collection.id.to_inner()),
        );

        collection.is_paused = false;
    }

    /// Withdraw the balance of the collection.
    public fun withdraw(collection: &mut Collection, cap: &Creator, ctx: &mut TxContext) {
        cap.assert_collection_creator(collection.id.to_inner());

        withdraw_balance(&mut collection.balance, ctx)
    }

    // === Getter functions ===
    public fun get_start_timestamp_ms(collection: &Collection): (u64, u64, u64) {
        (
            collection.whitelist_start_timestamp_ms,
            collection.custom_start_timestamp_ms,
            collection.start_timestamp_ms,
        )
    }

    // === Package Functions ===

    // === Private Functions ===
    fun top_up(collection: &mut Collection, payment: Coin<SUI>) {
        coin::put(&mut collection.balance, payment)
    }

    // === Private Functions: asserts

    fun assert_paused(collection: &Collection) {
        assert!(collection.is_paused, error::notPausedStatus!());
    }

    fun assert_not_paused(collection: &Collection) {
        assert!(!collection.is_paused, error::notPausedStatus!());
    }

    fun assert_whitelist_enabled(collection: &Collection) {
        assert!(collection.whitelist_enabled, error::whitelistPhaseNotEnabled!());
    }

    fun assert_item_not_minted<T: key + store>(collection: &Collection, item: &T) {
        let item_id = object::id(item);
        assert!(!collection.items.contains(item_id), error::itemAlreadyMinted!());
    }

    fun assert_item_type<T: key + store>(collection: &Collection, _item: &T) {
        let collection_item_type = collection.item_type.into_bytes();
        let item_type = type_to_string<T>().into_bytes();

        assert!(collection_item_type == item_type, error::itemTypeMismatch!());
    }

    fun assert_kiosk_enabled(collection: &Collection) {
        assert!(collection.is_kiosk, error::kioskNotEnabled!());
    }

    // fun assert_kiosk_disabled(collection: &Collection) {
    //     assert!(!collection.is_kiosk, error::kioskNotDisabled!());
    // }

    // === Private Functions: utils

    /// Optionally enable whitelist phase.
    fun enable_whitelist_impl(
        collection: &mut Collection,
        whitelist_price: u64,
        whitelist_supply: u64,
        whitelist_start_timestamp_ms: u64,
        clock: &Clock,
    ) {
        assert!(
            whitelist_start_timestamp_ms < collection.start_timestamp_ms,
            error::publicStartBeforeWhitelist!(),
        );
        assert!(
            whitelist_start_timestamp_ms >= clock.timestamp_ms(),
            error::invalidStartTimestamp!(),
        );
        assert!(whitelist_supply <= collection.supply, error::invalidWhitelistSupply!());

        collection.whitelist_enabled = true;
        collection.whitelist_price = whitelist_price;
        collection.whitelist_supply = whitelist_supply;
        collection.whitelist_start_timestamp_ms = whitelist_start_timestamp_ms;
    }

    fun enable_custom_impl(
        collection: &mut Collection,
        custom_name: String,
        custom_price: u64,
        custom_supply: u64,
        custom_start_timestamp_ms: u64,
        clock: &Clock,
    ) {
        assert!(
            custom_start_timestamp_ms < collection.start_timestamp_ms,
            error::publicStartBeforeCustom!(),
        );
        assert!(custom_start_timestamp_ms >= clock.timestamp_ms(), error::invalidStartTimestamp!());
        assert!(custom_supply <= collection.supply, error::invalidCustomSupply!());
        collection.custom_enabled = true;
        collection.custom_name = custom_name;
        collection.custom_price = custom_price;
        collection.custom_supply = custom_supply;
        collection.custom_start_timestamp_ms = custom_start_timestamp_ms;
    }

    // / By default lock rule is added to the policy.
    // / Creator can later modify the policy via TransferPolicy and TransferPolicyCap.
    #[allow(lint(share_owned, self_transfer))]
    fun create_policy_impl<T>(policy: &mut TransferPolicy<T>, policy_cap: &TransferPolicyCap<T>) {
        if (!has_rule<T, kiosk_lock_rule::Rule>(policy)) {
            kiosk_lock_rule::add(policy, policy_cap);
        };
    }

    /// Checks if the address is in the whitelist.
    /// Checks if the address exceeded the whitelist allocation.
    /// Decrements the allocation.
    fun check_whitelist_mint_allowed(collection: &mut Collection, address: address) {
        assert!(collection.whitelist.contains(address), error::addressNotInWhitelist!());
        assert!(collection.whitelist[address] > 0, error::addressAllocationExceeded!());

        let current_allocation = &mut collection.whitelist[address];
        *current_allocation = *current_allocation - 1;
    }

    /// Checks if the address not exceeded the max items per address.
    /// Increments the items per address.
    /// Not called for whitelist minting. So whitelist addresses can participate in public minting.
    fun check_mint_allowed(collection: &mut Collection, address: address) {
        if (!collection.items_per_address.contains(address)) {
            collection.items_per_address.add(address, 0);
        };
        let current_items_per_address = &mut collection.items_per_address[address];
        assert!(
            *current_items_per_address < collection.max_items_per_address,
            error::maxItemsPerAddressExceeded!(),
        );
        *current_items_per_address = *current_items_per_address + 1;
    }

    fun mint_impl<T: key + store>(
        collection: &mut Collection,
        launchpad: &mut Launchpad,
        item: &T,
        mut payment: Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        collection.assert_not_paused();
        launchpad.assert_collection_not_paused(collection.id.to_inner());
        launchpad.assert_collection_approved(collection.id.to_inner());
        assert_item_type<T>(collection, item);
        assert_item_not_minted(collection, item);

        let sender = ctx.sender();

        let phase = collection.phase(launchpad, clock);
        match (phase) {
            CollectionPhase::NotStarted => abort error::mintNotStarted!(),
            CollectionPhase::Whitelist => {
                collection.assert_whitelist_enabled();
                collection.check_whitelist_mint_allowed(sender);
                assert!(
                    collection.items.length() < collection.whitelist_supply,
                    error::whitelistMintEnded!(),
                );
                let fee = payment_split_fee(
                    &mut payment,
                    collection.whitelist_price,
                    launchpad.fee_percentage(object::id(collection)),
                    ctx,
                );
                launchpad.top_up(fee);
            },
            CollectionPhase::Custom => {
                assert!(
                    collection.items.length() < collection.custom_supply,
                    error::customMintEnded!(),
                );
                let fee = payment_split_fee(
                    &mut payment,
                    collection.custom_price,
                    launchpad.fee_percentage(object::id(collection)),
                    ctx,
                );
                launchpad.top_up(fee);
                collection.check_mint_allowed(sender);
            },
            CollectionPhase::Public => {
                assert!(collection.items.length() < collection.supply, error::mintEnded!());
                let fee = payment_split_fee(
                    &mut payment,
                    collection.price,
                    launchpad.fee_percentage(object::id(collection)),
                    ctx,
                );
                launchpad.top_up(fee);
                collection.check_mint_allowed(sender);
            },
            CollectionPhase::Ended => abort error::mintEnded!(),
        };
        collection.top_up(payment);

        collection.items.add(object::id(item), true);

        emit(ItemMintedEvent {
            collection: collection.id.to_inner(),
            item: object::id(item),
            address: sender,
        });
    }

    // === Test Functions ===

    #[test_only]
    public fun not_started_phase_testing(): CollectionPhase {
        CollectionPhase::NotStarted
    }

    #[test_only]
    public fun whitelist_phase_testing(): CollectionPhase {
        CollectionPhase::Whitelist
    }

    #[test_only]
    public fun custom_phase_testing(): CollectionPhase {
        CollectionPhase::Custom
    }

    #[test_only]
    public fun public_phase_testing(): CollectionPhase {
        CollectionPhase::Public
    }

    //     #[test_only]
    //     public fun test_init() {
    //
    // }

    // #[test]
    // public fun test_vector_macro_all() {
    //     let allocations = vector[1, 2, 3];
    //     // let table = table::new(gcc)
    //
    //     let is_valid_allocations = allocations.all!(|allocation| {
    //         *allocation > 0
    //     });
    //
    //     assert!(is_valid_allocations);
    // }
}
