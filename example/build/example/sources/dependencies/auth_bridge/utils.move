module auth_bridge::utils {
    use auth_bridge::errors;
    use std::{bcs, string::{Self, String}, type_name::get_with_original_ids};
    use sui::hash;

    const ED25519_FLAG: u8 = 0x00;
    const ED25519_SIG_LEN: u64 = 64;
    const ED25519_PK_LEN: u64 = 32;
    const Expected_len: u64 = 1 + ED25519_SIG_LEN + ED25519_PK_LEN;

    /// Extracts the raw signature and public key from a full signature vector.
    /// @returns (raw_signature: vector<u8>, raw_public_key: vector<u8>)
    public fun extract_signature_and_pubilc_key(full_sig: vector<u8>): (vector<u8>, vector<u8>) {
        let len = full_sig.length();
        assert!(len == Expected_len, errors::wrongFullSignatureLength!());

        let flag = *full_sig.borrow(0);
        assert!(flag == ED25519_FLAG, errors::notEd25519Signature!());

        let mut raw_sig = vector::empty<u8>();
        let mut index_sig = 1; // Skip the first byte (the flag)
        while (index_sig <= ED25519_SIG_LEN) {
            raw_sig.push_back(*full_sig.borrow(index_sig));
            index_sig = index_sig + 1;
        };

        let mut raw_public_key = vector::empty<u8>();
        let mut i_public_key = index_sig; // Now index_sig is 65
        while (i_public_key < Expected_len) {
            raw_public_key.push_back(*full_sig.borrow(i_public_key));
            i_public_key = i_public_key + 1;
        };

        (raw_sig, raw_public_key)
    }

    /// Prepares a message for signing by adding the intent prefix and hashing it.
    /// @returns (hashed_message: vector<u8>)
    public fun hash_message(message: vector<u8>): vector<u8> {
        let message_bcs = bcs::to_bytes(&message);
        let mut message_with_intent = x"030000"; // Sign personal message
        message_with_intent.append(message_bcs);
        hash::blake2b256(&message_with_intent)
    }

    public(package) fun derive_address_from_ed25519(public_key: vector<u8>): address {
        assert!(public_key.length() == 32, 102);

        let mut concatened: vector<u8> = vector::singleton(0);
        concatened.append(public_key);

        sui::address::from_bytes(sui::hash::blake2b256(&concatened))
    }

    public(package) fun type_to_string<T>(): String {
        string::from_ascii(get_with_original_ids<T>().into_string())
    }
}
