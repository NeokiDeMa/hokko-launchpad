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

    public enum LaunchpadCollectionState has drop, store {
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
        collections: Table<ID, LaunchpadCollectionState>,
        collection_types: Table<String, bool>,
    }

    // === Events ===
    // public struct LaunchpadCollectionPendingEvent has copy, drop (ID)

    public struct LaunchpadCollectionApprovedEvent has copy, drop (ID)

    public struct LaunchpadCollectionRejectedEvent has copy, drop (ID)

    public struct LaunchpadCollectionPausedEvent has copy, drop (ID)

    public struct LaunchpadCollectionResumedEvent has copy, drop (ID)

    // === Init ===

    fun init(otw: LAUNCHPAD, ctx: &mut TxContext) {
        let publisher = package::claim(otw, ctx);

        let launchpad = Launchpad {
            id: object::new(ctx),
            version: VERSION,
            base_fee_percentage: DEFAULT_FEE_PERCENTAGE,
            custom_fee_percentage: table::new(ctx),
            balance: balance::zero(),
            collections: table::new(ctx),
            collection_types: table::new(ctx),
        };

        transfer::public_transfer(publisher, ctx.sender());
        transfer::share_object(launchpad);
    }

    // === Public Functions ===

    // === View Functions ===
    public fun collection_status_appoved(_: &Launchpad): LaunchpadCollectionState {
        LaunchpadCollectionState::Approved
    }

    public fun collection_state(launchpad: &Launchpad, collection: ID): LaunchpadCollectionState {
        if (!launchpad.collections.contains(collection)) {
            return LaunchpadCollectionState::NotFound
        };

        let state = &launchpad.collections[collection];

        match (state) {
            LaunchpadCollectionState::Pending => LaunchpadCollectionState::Pending,
            LaunchpadCollectionState::Approved => LaunchpadCollectionState::Approved,
            LaunchpadCollectionState::Rejected => LaunchpadCollectionState::Rejected,
            LaunchpadCollectionState::Paused => LaunchpadCollectionState::Paused,
            _ => LaunchpadCollectionState::NotFound,
        }
    }

    public fun fee_percentage(launchpad: &Launchpad, collection: ID): u64 {
        if (launchpad.custom_fee_percentage.contains(collection)) {
            let custom_fee = launchpad.custom_fee_percentage[collection];
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

    public fun set_custom_fee(
        launchpad: &mut Launchpad,
        _: &RoleCap<Admin>,
        collection: ID,
        fee: u64,
    ) {
        assert!(launchpad.collections.contains(collection), error::collectionNotFound!());
        if (launchpad.custom_fee_percentage.contains(collection)) {
            let old_fee = launchpad.custom_fee_percentage.borrow_mut(collection);
            *old_fee = fee;
        } else { launchpad.custom_fee_percentage.add(collection, fee); };
    }

    /// Approve a collection.
    /// Once approved, collection creator can launch the collection.
    public fun approve_collection(
        launchpad: &mut Launchpad,
        _: &RoleCap<Admin>,
        collection: ID,
        custom_fee: Option<u64>,
    ) {
        launchpad.assert_collection_exists(collection);
        launchpad.assert_collection_state_pending(collection);

        let state = &mut launchpad.collections[collection];
        if (custom_fee.is_some()) {
            let fee = custom_fee.destroy_some();
            launchpad.custom_fee_percentage.add(collection, fee);
        } else {
            custom_fee.destroy_none();
        };
        emit(LaunchpadCollectionApprovedEvent(collection));

        *state = LaunchpadCollectionState::Approved;
    }

    /// Reject a collection.
    /// Once rejected, collection creator cannot launch the collection.
    public fun reject_collection(launchpad: &mut Launchpad, _: &RoleCap<Admin>, collection: ID) {
        launchpad.assert_collection_exists(collection);
        launchpad.assert_collection_state_pending(collection);

        let state = &mut launchpad.collections[collection];

        emit(LaunchpadCollectionRejectedEvent(collection));

        *state = LaunchpadCollectionState::Rejected;
    }

    /// Pause a collection by admin.
    /// Can only be called if the collection is approved.
    public fun pause_collection(launchpad: &mut Launchpad, _: &RoleCap<Admin>, collection: ID) {
        launchpad.assert_collection_exists(collection);

        let state = &mut launchpad.collections[collection];
        assert!(state == LaunchpadCollectionState::Approved, error::collectionNotApproved!());

        emit(LaunchpadCollectionPausedEvent(collection));

        *state = LaunchpadCollectionState::Paused;
    }

    /// Resume a collection by admin.
    /// Can only be called if the collection is paused.
    public fun resume_collection(launchpad: &mut Launchpad, _: &RoleCap<Admin>, collection: ID) {
        launchpad.assert_collection_exists(collection);

        let state = &mut launchpad.collections[collection];
        assert!(state == LaunchpadCollectionState::Paused, error::collectionNotPaused!());

        emit(LaunchpadCollectionResumedEvent(collection));

        *state = LaunchpadCollectionState::Approved;
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

    /// Registers a collection.
    /// Once initialized, Admin can approve or reject the collection.
    public(package) fun register_collection(
        launchpad: &mut Launchpad,
        collection: ID,
        // To prevent multiple creations from same package
        collection_type: String,
    ) {
        let state = LaunchpadCollectionState::Pending;

        // emit(LaunchpadCollectionPendingEvent(collection));

        launchpad.collections.add(collection, state);

        assert!(!launchpad.collection_types.contains(collection_type), error::typeAlreadyExists!());
        launchpad.collection_types.add(collection_type, true);
    }

    /// Top up the launchpad balance.
    /// Used to pay the fee for collection launch.
    public(package) fun top_up(launchpad: &mut Launchpad, fee: Coin<SUI>) {
        coin::put(&mut launchpad.balance, fee)
    }

    // === Package Functions: asserts

    public(package) fun assert_collection_approved(launchpad: &Launchpad, collection: ID) {
        assert!(
            launchpad.collection_state(collection) == LaunchpadCollectionState::Approved,
            error::collectionNotApproved!(),
        );
    }

    public(package) fun assert_collection_not_paused(launchpad: &Launchpad, collection: ID) {
        assert!(
            launchpad.collection_state(collection) != LaunchpadCollectionState::Paused,
            error::collectionPaused!(),
        );
    }

    // === Private Functions ===

    fun assert_collection_exists(launchpad: &Launchpad, collection: ID) {
        assert!(launchpad.collections.contains(collection), error::collectionNotFound!())
    }

    fun assert_collection_state_pending(launchpad: &Launchpad, collection: ID) {
        let state = &launchpad.collections[collection];
        assert!(
            state == LaunchpadCollectionState::Pending || state == LaunchpadCollectionState::Rejected,
            error::collectionNotPending!(),
        )
    }
    #[test_only]
    public fun test_init(ctx: &mut TxContext) {
        let otw = LAUNCHPAD {};
        init(otw, ctx);
    }
    #[test_only]
    public fun pending_collection_state_testing(): LaunchpadCollectionState {
        LaunchpadCollectionState::Pending
    }

    #[test_only]
    public fun rejected_collection_state_testing(): LaunchpadCollectionState {
        LaunchpadCollectionState::Rejected
    }
    #[test_only]
    public fun paused_collection_state_testing(): LaunchpadCollectionState {
        LaunchpadCollectionState::Paused
    }
}

// === Test Functions ===
