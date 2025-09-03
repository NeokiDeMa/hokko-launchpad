module launchpad::launchpad {
    use access_control::access_control::RoleCap;
    use launchpad::{error, roles::Admin, utils::withdraw_balance};
    use std::string::String;
    use sui::{
        balance::{Self, Balance},
        coin::{Self, Coin},
        event::emit,
        package,
        sui::SUI,
        table::{Self, Table}
    };

    // === Constants ===

    const DEFAULT_FEE_PERCENTAGE: u64 = 200;
    const VERSION: u64 = 1;

    // === Structs ===

    public struct LAUNCHPAD has drop {}

    public enum LaunchpadState has drop, store {
        NotFound,
        Pending,
        Approved,
        Rejected,
        Paused,
    }

    public struct Launchpad has key {
        id: UID,
        version: u64,
        base_fee_percentage: u64,
        custom_fee_percentage: Table<ID, u64>,
        balance: Balance<SUI>,
        launch_ids: Table<ID, LaunchpadState>,
        collection_types: Table<String, bool>,
    }

    // === Events ===
    // public struct LaunchpadPendingEvent has copy, drop (ID)

    public struct LaunchpadApprovedEvent has copy, drop (ID)

    public struct LaunchpadRejectedEvent has copy, drop (ID)

    public struct LaunchpadPausedEvent has copy, drop (ID)

    public struct LaunchpadResumedEvent has copy, drop (ID)

    // === Init ===

    fun init(otw: LAUNCHPAD, ctx: &mut TxContext) {
        let publisher = package::claim(otw, ctx);

        let launchpad = Launchpad {
            id: object::new(ctx),
            version: VERSION,
            base_fee_percentage: DEFAULT_FEE_PERCENTAGE,
            custom_fee_percentage: table::new(ctx),
            balance: balance::zero(),
            launch_ids: table::new(ctx),
            collection_types: table::new(ctx),
        };

        transfer::public_transfer(publisher, ctx.sender());
        transfer::share_object(launchpad);
    }

    // === Public Functions ===

    // === View Functions ===
    public fun launch_status_appoved(_: &Launchpad): LaunchpadState {
        LaunchpadState::Approved
    }

    public fun launch_state(launchpad: &Launchpad, launch: ID): LaunchpadState {
        if (!launchpad.launch_ids.contains(launch)) {
            return LaunchpadState::NotFound
        };

        let state = &launchpad.launch_ids[launch];

        match (state) {
            LaunchpadState::Pending => LaunchpadState::Pending,
            LaunchpadState::Approved => LaunchpadState::Approved,
            LaunchpadState::Rejected => LaunchpadState::Rejected,
            LaunchpadState::Paused => LaunchpadState::Paused,
            _ => LaunchpadState::NotFound,
        }
    }

    public fun fee_percentage(launchpad: &Launchpad, launch: ID): u64 {
        if (launchpad.custom_fee_percentage.contains(launch)) {
            let custom_fee = launchpad.custom_fee_percentage[launch];
            // Return the minimum of custom fee and base fee
            std::u64::min(custom_fee, launchpad.base_fee_percentage)
        } else {
            launchpad.base_fee_percentage
        }
    }

    // === Admin Functions ===

    public fun set_base_fee(launchpad: &mut Launchpad, _: &RoleCap<Admin>, fee: u64) {
        launchpad.base_fee_percentage = fee;
    }

    public fun set_custom_fee(launchpad: &mut Launchpad, _: &RoleCap<Admin>, launch: ID, fee: u64) {
        assert!(launchpad.launch_ids.contains(launch), error::launchNotFound!());
        if (launchpad.custom_fee_percentage.contains(launch)) {
            let old_fee = launchpad.custom_fee_percentage.borrow_mut(launch);
            *old_fee = fee;
        } else { launchpad.custom_fee_percentage.add(launch, fee); };
    }

    /// Approve a launch.
    /// Once approved, launch creator can launch the launch.
    public fun approve_launch(
        launchpad: &mut Launchpad,
        _: &RoleCap<Admin>,
        launch: ID,
        custom_fee: Option<u64>,
    ) {
        launchpad.assert_launch_exists(launch);
        launchpad.assert_launch_state_pending(launch);

        let state = &mut launchpad.launch_ids[launch];
        if (custom_fee.is_some()) {
            let fee = custom_fee.destroy_some();
            launchpad.custom_fee_percentage.add(launch, fee);
        } else {
            custom_fee.destroy_none();
        };
        emit(LaunchpadApprovedEvent(launch));

        *state = LaunchpadState::Approved;
    }

    /// Reject a launch.
    /// Once rejected, launch creator cannot launch the launch.
    public fun reject_launch(launchpad: &mut Launchpad, _: &RoleCap<Admin>, launch: ID) {
        launchpad.assert_launch_exists(launch);
        launchpad.assert_launch_state_pending(launch);

        let state = &mut launchpad.launch_ids[launch];

        emit(LaunchpadRejectedEvent(launch));

        *state = LaunchpadState::Rejected;
    }

    /// Pause a launch by admin.
    /// Can only be called if the launch is approved.
    public fun pause_launch(launchpad: &mut Launchpad, _: &RoleCap<Admin>, launch: ID) {
        launchpad.assert_launch_exists(launch);

        let state = &mut launchpad.launch_ids[launch];
        assert!(state == LaunchpadState::Approved, error::launchNotApproved!());

        emit(LaunchpadPausedEvent(launch));

        *state = LaunchpadState::Paused;
    }

    /// Resume a launch by admin.
    /// Can only be called if the launch is paused.
    public fun resume_launch(launchpad: &mut Launchpad, _: &RoleCap<Admin>, launch: ID) {
        launchpad.assert_launch_exists(launch);

        let state = &mut launchpad.launch_ids[launch];
        assert!(state == LaunchpadState::Paused, error::launchNotPaused!());

        emit(LaunchpadResumedEvent(launch));

        *state = LaunchpadState::Approved;
    }

    /// Withdraw the balance from the launchpad by admin.
    public fun withdraw(launchpad: &mut Launchpad, _: &RoleCap<Admin>, ctx: &mut TxContext) {
        withdraw_balance(&mut launchpad.balance, ctx)
    }

    entry fun migrate(self: &mut Launchpad, _: &RoleCap<Admin>) {
        assert!(self.version < VERSION, error::notUpgraded!());
        self.version = VERSION;
    }

    // === Package Functions ===

    public(package) fun assert_version(self: &Launchpad) {
        assert!(self.version == VERSION, error::wrongVersion!());
    }

    /// Registers a launch.
    /// Once initialized, Admin can approve or reject the launch.
    public(package) fun register_launch(
        launchpad: &mut Launchpad,
        launch: ID,
        // To prevent multiple creations from same package
        launch_type: String,
    ) {
        let state = LaunchpadState::Pending;

        // emit(LaunchpadPendingEvent(launch));

        launchpad.launch_ids.add(launch, state);

        assert!(!launchpad.collection_types.contains(launch_type), error::typeAlreadyExists!());
        launchpad.collection_types.add(launch_type, true);
    }

    /// Top up the launchpad balance.
    /// Used to pay the fee for launch launch.
    public(package) fun top_up(launchpad: &mut Launchpad, fee: Coin<SUI>) {
        coin::put(&mut launchpad.balance, fee)
    }

    // === Package Functions: asserts

    public(package) fun assert_launch_approved(launchpad: &Launchpad, launch: ID) {
        assert!(
            launchpad.launch_state(launch) == LaunchpadState::Approved,
            error::launchNotApproved!(),
        );
    }

    public(package) fun assert_launch_not_paused(launchpad: &Launchpad, launch: ID) {
        assert!(launchpad.launch_state(launch) != LaunchpadState::Paused, error::launchPaused!());
    }

    // === Private Functions ===

    fun assert_launch_exists(launchpad: &Launchpad, launch: ID) {
        assert!(launchpad.launch_ids.contains(launch), error::launchNotFound!())
    }

    fun assert_launch_state_pending(launchpad: &Launchpad, launch: ID) {
        let state = &launchpad.launch_ids[launch];
        assert!(
            state == LaunchpadState::Pending || state == LaunchpadState::Rejected,
            error::launchNotPending!(),
        )
    }
    #[test_only]
    public fun test_init(ctx: &mut TxContext) {
        let otw = LAUNCHPAD {};
        init(otw, ctx);
    }
    #[test_only]
    public fun pending_launch_state_testing(): LaunchpadState {
        LaunchpadState::Pending
    }

    #[test_only]
    public fun rejected_launch_state_testing(): LaunchpadState {
        LaunchpadState::Rejected
    }
    #[test_only]
    public fun paused_launch_state_testing(): LaunchpadState {
        LaunchpadState::Paused
    }
}

// === Test Functions ===
