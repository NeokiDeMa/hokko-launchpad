module auth_bridge::errors {
    public macro fun wrongFullSignatureLength(): u64 {
        101
    }
    public macro fun notEd25519Signature(): u64 {
        102
    }
    public macro fun protocolAddrassNotMatch(): u64 {
        103
    }
}
