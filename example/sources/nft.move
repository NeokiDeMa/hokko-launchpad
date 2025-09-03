// Nft NFT Module
// Is a module for creating and managing Nft NFTs on the Sui blockchain.
// It includes minting functionality, attributes, and display setup.
module example::nft {
    use kiosk::{kiosk_lock_rule, royalty_rule};
    use launchpad::{launch_manager::{Self, Launch}, launchpad::Launchpad};
    use std::string::String;
    use sui::{
        clock::Clock,
        coin::Coin,
        display,
        event::emit,
        package,
        sui::SUI,
        transfer_policy::{Self, TransferPolicy}
    };

    public struct NFT has drop {}

    // ============== Structs ==============
    public struct Config has key, store {
        id: UID,
        max_supply: u64,
        mint_count: u64,
    }

    public struct MintCap has key, store {
        id: UID,
    }

    public struct Attributes has drop, store {
        key: String,
        value: String,
    }

    public struct Nft has key, store {
        id: UID,
        name: String,
        image_url: String,
        description: String,
        attributes: vector<Attributes>,
        rarity: u64,
    }

    // ============== Errors ==============
    const EMaxSupplyReached: u64 = 0;

    // ============== Events ==============

    public struct MintNftEvent has copy, drop {
        nft_id: ID,
    }

    fun init(otw: NFT, ctx: &mut TxContext) {
        let pub = package::claim(otw, ctx);
        let sender = ctx.sender();
        let (tp, tp_cap) = transfer_policy::new<Nft>(&pub, ctx);

        setup_display(display::new<Nft>(&pub, ctx), sender);

        setup_rules(tp, tp_cap, sender);

        transfer::share_object(Config {
            id: object::new(ctx),
            max_supply: 3000,
            mint_count: 0,
        });

        transfer::public_transfer(pub, sender);
        transfer::transfer(MintCap { id: object::new(ctx) }, sender);
    }

    // ============== Public Functions ==============

    /// This approusch we do not need a Mintcap because we are passing in a payment. and the launpad setup
    /// enforces the right amount of tokens get sent in to the contract.
    public fun launchpad_mint(
        name: String,
        description: String,
        image_url: String,
        trait_keys: vector<String>,
        value_keys: vector<String>,
        payment: Coin<SUI>,
        clock: &Clock,
        policy: &TransferPolicy<Nft>,
        launch: &mut Launch,
        launchpad: &mut Launchpad,
        // Optional: Example of extra arguments from the JSON metadata
        rarity: u64,
        config: &mut Config,
        ctx: &mut TxContext,
    ) {
        config.assert_mintable();
        let nft = impl_mint(name, image_url, description, rarity, trait_keys, value_keys, ctx);
        emit(MintNftEvent { nft_id: nft.id.to_inner() });

        config.mint_count = config.mint_count + 1;

        launch_manager::mint_with_kiosk(launch, nft, payment, policy, clock, launchpad, ctx);
    }

    /// Example on how a create_nft function should look like, The mint cap than needs to be stored in the auth_bridge
    /// contract that hokko provides
    public fun create_nft(
        _: &MintCap, // This mintcap needs to be stored in a auth_bridge contarct that hokko will provide
        name: String,
        description: String,
        image_url: String,
        trait_keys: vector<String>,
        value_keys: vector<String>,
        rarity: u64, // Example on extra argument
        config: &mut Config, // Example on extra argument
        ctx: &mut TxContext,
    ): Nft {
        config.assert_mintable();

        let nft = impl_mint(name, image_url, description, rarity, trait_keys, value_keys, ctx);
        emit(MintNftEvent { nft_id: nft.id.to_inner() });

        config.mint_count = config.mint_count + 1;
        nft
    }

    // ============== Internal Functions ==============
    fun impl_mint(
        name: String,
        image_url: String,
        description: String,
        rarity: u64,
        keys: vector<String>,
        values: vector<String>,
        ctx: &mut TxContext,
    ): Nft {
        let mut attributes: vector<Attributes> = vector::empty<Attributes>();
        keys.zip_do!(values, |key, value| {
            let attr = Attributes {
                key,
                value,
            };
            vector::push_back(&mut attributes, attr);
        });

        Nft {
            id: object::new(ctx),
            name,
            image_url,
            description,
            attributes,
            rarity,
        }
    }

    // ============== Getter functions ==============

    public fun mint_count(self: &Config): u64 {
        self.mint_count
    }

    public fun max_supply(self: &Config): u64 {
        self.max_supply
    }

    //TODO: Get the correct data
    #[allow(lint(self_transfer))]
    fun setup_display(mut display: display::Display<Nft>, sender: address) {
        let banner_image = b"https://betbarkers.com/banner.png".to_string();
        let cover_url = b"https://betbarkers.com/cover.png".to_string();

        display.add(b"collection_name".to_string(), b"Nft".to_string());
        display.add(
            b"collection_description".to_string(),
            b"Nft is a collection of unique NFTs representing digital collectibles.".to_string(),
        );
        display.add(b"project_url".to_string(), b"https://betbarkers.com".to_string());
        display.add(b"creator".to_string(), b"Nft Team".to_string());
        display.add(b"banner_image".to_string(), banner_image);
        display.add(b"cover_url".to_string(), cover_url);
        display.add(b"name".to_string(), b"{name}".to_string());
        display.add(b"image_url".to_string(), b"{image_url}".to_string());
        display.add(b"description".to_string(), b"{description}".to_string());
        display.add(b"rarity".to_string(), b"{rarity}".to_string());
        transfer::public_transfer(display, sender);
    }

    #[allow(lint(share_owned, self_transfer))]
    fun setup_rules(
        mut tp: transfer_policy::TransferPolicy<Nft>,
        tp_cap: transfer_policy::TransferPolicyCap<Nft>,
        sender: address,
    ) {
        royalty_rule::add(&mut tp, &tp_cap, 200, 1_000_000_00);
        kiosk_lock_rule::add(&mut tp, &tp_cap);

        transfer::public_transfer(tp_cap, sender);
        transfer::public_share_object(tp);
    }

    // ============== Assertions =============
    fun assert_mintable(config: &Config) {
        assert!(config.mint_count < config.max_supply, EMaxSupplyReached);
    }

    #[test_only]
    public fun test_init(ctx: &mut TxContext) {
        init(NFT {}, ctx);
    }
}
