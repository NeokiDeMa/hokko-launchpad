#[allow(unused)]
module launchpad::error {
    // launchs package errors start with 100
    // Launchpad package errors start with 200

    #[test_only]
    const EInvalidPublisher: u64 = 101;
    #[test_only]
    const EInvalidWhitelistSupply: u64 = 102;
    #[test_only]
    const EInvalidWhitelistAllocation: u64 = 103;
    #[test_only]
    const EWhitelistPhaseNotEnabled: u64 = 104;
    #[test_only]
    const EInvalidVectorLength: u64 = 105;
    #[test_only]
    const EItemAlreadyMinted: u64 = 106;
    #[test_only]
    const EItemTypeMismatch: u64 = 107;
    #[test_only]
    const EPublicStartBeforeWhitelist: u64 = 108;
    #[test_only]
    const EInvalidStartTimestamp: u64 = 109;
    #[test_only]
    const ENotPausedStatus: u64 = 110;
    #[test_only]
    const EMintNotStarted: u64 = 111;
    #[test_only]
    const EWhitelistMintEnded: u64 = 112;
    #[test_only]
    const EMintEnded: u64 = 113;
    #[test_only]
    const EAddressNotInWhitelist: u64 = 114;
    #[test_only]
    const EAddressAllocationExceeded: u64 = 115;
    #[test_only]
    const EMaxItemsPerAddressExceeded: u64 = 116;
    #[test_only]
    const EKioskNotEnabled: u64 = 117;
    #[test_only]
    const EKioskNotDisabled: u64 = 118;
    #[test_only]
    const EInvalidCustomSupply: u64 = 119;
    #[test_only]
    const EPublicStartBeforeCustom: u64 = 120;
    #[test_only]
    const ECustomMintEnded: u64 = 121;

    #[test_only]
    const ElaunchNotFound: u64 = 201;
    #[test_only]
    const ElaunchNotPending: u64 = 202;
    #[test_only]
    const ElaunchNotApproved: u64 = 203;
    #[test_only]
    const ElaunchNotPaused: u64 = 204;
    #[test_only]
    const ElaunchPaused: u64 = 205;
    #[test_only]
    const ETypeAlreadyExists: u64 = 206;

    public(package) macro fun invalidPublisher(): u64 {
        101
    }

    public(package) macro fun invalidWhitelistSupply(): u64 {
        102
    }
    public(package) macro fun invalidWhitelistAllocation(): u64 {
        103
    }
    public(package) macro fun whitelistPhaseNotEnabled(): u64 {
        104
    }
    public(package) macro fun invalidVectorLength(): u64 {
        105
    }
    public(package) macro fun itemAlreadyMinted(): u64 {
        106
    }
    public(package) macro fun itemTypeMismatch(): u64 {
        107
    }
    public(package) macro fun publicStartBeforeWhitelist(): u64 {
        108
    }
    public(package) macro fun invalidStartTimestamp(): u64 {
        109
    }
    public(package) macro fun notPausedStatus(): u64 {
        110
    }
    public(package) macro fun mintNotStarted(): u64 {
        111
    }
    public(package) macro fun whitelistMintEnded(): u64 {
        112
    }
    public(package) macro fun mintEnded(): u64 {
        113
    }
    public(package) macro fun addressNotInWhitelist(): u64 {
        114
    }
    public(package) macro fun addressAllocationExceeded(): u64 {
        115
    }
    public(package) macro fun maxItemsPerAddressExceeded(): u64 {
        116
    }
    public(package) macro fun kioskNotEnabled(): u64 {
        117
    }
    public(package) macro fun kioskNotDisabled(): u64 {
        118
    }
    public(package) macro fun invalidCustomSupply(): u64 {
        119
    }
    public(package) macro fun publicStartBeforeCustom(): u64 {
        120
    }
    public(package) macro fun customMintEnded(): u64 {
        121
    }

    /// Launchpad package errors
    public(package) macro fun launchNotFound(): u64 {
        201
    }
    public(package) macro fun launchNotPending(): u64 {
        202
    }
    public(package) macro fun launchNotApproved(): u64 {
        203
    }
    public(package) macro fun launchNotPaused(): u64 {
        204
    }
    public(package) macro fun launchPaused(): u64 {
        205
    }
    public(package) macro fun typeAlreadyExists(): u64 {
        206
    }
    public(package) macro fun wrongAddress(): u64 {
        207
    }
    public(package) macro fun exceededMintAmount(): u64 {
        208
    }
    public(package) macro fun notUpgraded(): u64 {
        209
    }
    public(package) macro fun wrongVersion(): u64 {
        210
    }
}
