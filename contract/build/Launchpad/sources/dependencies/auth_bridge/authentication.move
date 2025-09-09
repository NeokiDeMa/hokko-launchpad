module auth_bridge::authentication {
    use auth_bridge::{errors, utils};
    use std::string::String;
    use sui::{
        borrow::{Self, Borrow, Referent},
        dynamic_field,
        ed25519::ed25519_verify,
        vec_map::{Self, VecMap}
    };

    public struct Registry has key, store {
        id: UID,
    }

    public struct Config has drop, store {
        // Address is the cap owner.
        address: address,
        // Input keys are the keys that are used to sign the message.
        input: vector<String>,
        // Output keys are the keys that are used to return the output of the protocol.
        output: VecMap<String, String>,
    }

    public struct HolderCap<T: key + store> has key, store {
        id: UID,
        cap: Referent<T>,
        owner: address,
    }

    public struct Protocol<phantom T> has key, store {
        id: UID,
        config: Config,
    }

    public struct Authentication<phantom T> has drop {
        initiater: address,
        output: VecMap<String, String>,
    }

    fun init(ctx: &mut TxContext) {
        transfer::share_object(Registry {
            id: sui::object::new(ctx),
        });
    }

    /// @notice: Creates a new Protocol object and shares it
    /// @param registry: The registry object that contains the protocol to prevent duplicates
    /// @param cap: The capability object that contains the key to be stored
    /// @param address: The public address that is the centralized address that signs the messages
    /// @param input_keys: The input keys that are used to sign the message
    /// @param output_keys: The output keys that are used to return the output of the protocol
    /// @param protocol: The objcet type will be registered in the registry
    #[allow(lint(share_owned))]
    public fun default<T: key + store, P>(
        registry: &mut Registry,
        cap: T,
        address: address,
        input_keys: vector<String>,
        output_keys: vector<String>,
        protocol: &P,
        ctx: &mut TxContext,
    ) {
        let protocol = new<P>(registry, address, input_keys, output_keys, protocol, ctx);
        create_and_store_cap<T, P>(&protocol, cap, ctx);
        transfer::share_object(protocol);
    }

    /// @notice: Make sure this otw is from a module that is not important for your protocol
    /// @param address: The pubilc address that is the centralized addross that signs the messages
    /// @param input_keys: The input keys that are used to sign the message
    /// @param output_keys: The output keys that are used to return the output of the protocol
    /// @param protocol: The objcet type will be registered in the registry
    /// @notice: Shares the Protocol object
    public fun new<P>(
        registry: &mut Registry,
        address: address,
        input_keys: vector<String>,
        output_keys: vector<String>,
        _: &P,
        ctx: &mut TxContext,
    ): Protocol<P> {
        dynamic_field::add(&mut registry.id, utils::type_to_string<P>(), true);

        let output = output_keys.fold!<String, VecMap<String, String>>(
            vec_map::empty<String, String>(),
            |mut acc, v| {
                acc.insert(v, b"".to_string());
                acc
            },
        );

        let config = Config {
            address,
            input: input_keys,
            output,
        };
        Protocol<P> {
            id: sui::object::new(ctx),
            config,
        }
    }

    /// @notice: Creates a capability that contains the key and stores it in the protocol
    /// @param protocol: The protocol object that contains the configuration
    /// @param cap: The capability object that contains the key to be stored
    public fun create_and_store_cap<T: key + store, P>(
        _: &Protocol<P>,
        cap: T,
        ctx: &mut TxContext,
    ) {
        let owner = ctx.sender();
        let uid = sui::object::new(ctx);
        let mint_cap = HolderCap<T> {
            id: uid,
            cap: borrow::new(cap, ctx),
            owner,
        };

        transfer::share_object(mint_cap);
    }

    /// @notice: Sign in to the protocol with a full signature, It is important the order of the keys is the same as when the protocol object was created
    /// @param protocol: The protocol object that contains the configuration
    /// @param cap: The capability object that contains the key to be signed
    /// @param full_sig: The full signature that contains the raw signature and the public key
    /// @param data: The data that is used to sign the message
    /// @notice: The T type is the same type as the key in the capability
    /// @returns: Authentication that is used for contract operations
    public fun signin<T: key + store, P>(
        protocol: &Protocol<P>,
        cap: &mut HolderCap<T>,
        full_sig: vector<u8>,
        data: VecMap<String, String>,
        ctx: &mut TxContext,
    ): Authentication<T> {
        let sender = ctx.sender();

        let (raw_sign, raw_public_key) = utils::extract_signature_and_pubilc_key(full_sig);
        let protocol_keys = protocol.into_keys();

        assert!(
            protocol.config.address == utils::derive_address_from_ed25519(raw_public_key),
            errors::protocolAddrassNotMatch!(),
        );

        let mut output = vec_map::empty<String, String>();
        let msg: String = protocol_keys.fold!(b"0x".to_string(), |mut acc, v| {
            if (v == b"sender".to_string()) {
                acc.append(ctx.sender().to_string())
            } else if (v == b"type".to_string()) {
                let mut appe = b"0x".to_string();
                appe.append(utils::type_to_string<T>());
                acc.append(appe)
            } else { acc.append(*data.get(&v)); };
            if (protocol.config.output.contains(&v)) {
                output.insert(v, *data.get(&v))
            };
            acc
        });

        let message = utils::hash_message(msg.into_bytes());

        assert!(
            ed25519_verify(&raw_sign, &raw_public_key, &message),
            errors::notEd25519Signature!(),
        );
        dynamic_field::add(&mut cap.id, raw_public_key, true);
        Authentication<T> {
            initiater: sender,
            output,
        }
    }

    /// @notice: Destroys the protocol object and capability than sends the key back to the owner
    /// @param self: The capability object that contains the key to be destroyed
    public fun destroy<T: key + store, P>(
        self: HolderCap<T>,
        protocol: Protocol<P>,
        ctx: &mut TxContext,
    ) {
        let sender = ctx.sender();
        assert!(self.owner == sender, 102);
        let HolderCap {
            id,
            cap,
            ..,
        } = self;
        let cap = borrow::destroy(cap);

        transfer::public_transfer(cap, sender);
        id.delete();
        let Protocol { id, .. } = protocol;
        id.delete();
    }

    /// @notice: Takes the key from the capability and returns it with a borrow
    /// @param self: The capability object that contains the key to be taken
    /// @param _: The authentication object that is used to verify the key
    /// @returns: The key and a borrow that is used to return the key later
    public fun take_key<T: key + store>(
        self: &mut HolderCap<T>,
        _: Authentication<T>,
    ): (T, Borrow) {
        self.cap.borrow()
    }

    /// @notice: Returns the key to the capability with a borrow
    /// @param self: The capability object that contains the key to be returned
    /// @param value: The key that is returned to the capability
    /// @param borrow: The borrow that is used to return the key
    /// @notice: The key must be the same as the one taken from the capability
    /// @notice: The borrow must be the same as the one returned from the take_key
    public fun return_key<T: key + store>(self: &mut HolderCap<T>, value: T, borrow: Borrow) {
        self.cap.put_back(value, borrow);
    }

    /// @notice: Gettur for the input keys of the protocol
    public fun into_keys<P>(self: &Protocol<P>): vector<String> {
        self.config.input
    }

    public fun protocol_ouput_keys<P>(self: &Protocol<P>): vector<String> {
        self.config.output.keys()
    }

    public fun into_output_keys<T>(self: &Authentication<T>): vector<String> {
        self.output.keys()
    }

    public fun get_initiator<T>(self: &Authentication<T>): address {
        self.initiater
    }

    public fun get_output<T>(self: &Authentication<T>): VecMap<String, String> {
        self.output
    }

    public fun get_one_output<T>(self: &Authentication<T>, key: &String): &String {
        self.output.get(key)
    }

    #[test_only]
    public fun test_init(ctx: &mut TxContext) {
        init(ctx)
    }
}
