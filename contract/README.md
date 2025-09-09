### Guide for Integrating Your NFT Contract with Hokko Launchpad

This guide outlines two primary ways to integrate your custom NFT contract with the Hokko Launchpad, providing flexibility based on your contract's design. In both approaches, strict adherence to the function signatures and argument order is crucial for successful integration.

#### 1. Smart Contract Oriented Integration

This approach is generally recommended for its security and seamlessness, as your NFT contract directly manages the minting process and integrates with the Hokko Launchpad.

**Requirements:**

*   Your NFT contract must implement a public function named `launchpad_mint`.
*   This function *must* have the exact signature and argument order as shown below.
*   **Optional:** If your collection requires additional custom inputs, they would be appended to the end of the required arguments.

````move
// filepath: README.md
// ...existing code...
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
    // custom_string: String,
    // custom_bool: Bool,
    // custom_u64: u64,
    // custom_struct_ref_1: &0x1234::new_module::other_struct,
    // custom_struct_ref_2: &0x5678::another_module::my_struct
    ctx: &mut TxContext
) {
    // This is where you implement your custom logic to create your NFT.
    // Replace `create_nft()` with your actual NFT creation function.
    // Ensure any extra arguments are passed down if your create_nft also uses them.
    let nft: Nft = create_nft();

    // After creating the NFT, pass it to the launch manager for minting.
    launch_manager::mint_with_kiosk<Nft>(
        launch,
        nft,
        payment,
        policy,
        clock,
        launchpad,
        ctx
    );
}
````

**Explanation:**

1.  **`create_nft()`:** This placeholder represents your contract's internal function responsible for constructing the `Nft` object based on the provided metadata (`name`, `description`, `image_url`, `tarit_keys`, `value_keys`).
2.  **`launch_manager::mint_with_kiosk`:** This function is provided by the Hokko Launchpad to handle the final steps of minting the NFT into the associated kiosk, applying the transfer policy, and interacting with the launchpad mechanics.

#### 2. Client Focused Integration

In this approach, your NFT contract focuses solely on the creation of the NFT object than store the mintcap in the Authentication module that Hokko is providing, and the Hokko client or a separate module handles the subsequent steps of placing it into the launchpad.

**Requirements:**

*   Your NFT contract must implement a public function named `create_nft`.
*   This function *must* have the exact signature and argument order as shown below.
*   **Optional:** If your NFT creation requires additional custom inputs, they would be appended to the end of the required arguments.

````move
// ...existing code...
public fun create_nft(
    mint_cap: &MintCap,
    name: String,
    description: String,
    image_url: String,
    trait_keys: vector<String>,
    value_keys: vector<String>,
    // Optional: Example of extra arguments from the JSON metadata
    // custom_string: String,
    // custom_bool: Bool,
    // custom_u64: u64,
    // custom_struct_ref_1: &0x1234::new_module::other_struct,
    // custom_struct_ref_2: &0x5678::another_module::my_struct
    ctx: &mut TxContext
): Nft {
    // Implement your custom logic to assemble your NFT here.
    // Use the provided arguments, including any custom ones, to construct your NFT.
    // This function should return the newly created Nft object.
}
````

**Explanation:**

1.  **`mint_cap: &MintCap`:** This capability object is typically required by NFT collection contracts to authorize the creation of new NFTs.
2.  **NFT Construction:** Inside this function, you will write the logic to construct your specific `Nft` struct, populating it with the provided `name`, `description`, `image_url`, `tarit_keys`, `value_keys`, and any `custom_` arguments.
3.  **Return `Nft`:** The function must return the fully assembled `Nft` object, which the Hokko Launchpad client will then use to mint.

#### Common Considerations for NFT Metadata

Both `launchpad_mint` and `create_nft` functions include `tarit_keys: vector<String>` and `value_keys: vector<String>`. These arguments are used to pass dynamic attributes (traits) for your NFTs.

*   `tarit_keys`: Represents the names or types of your NFT's traits (e.g., "Background", "Body", "Accessory").
*   `value_keys`: Represents the corresponding values for those traits (e.g., "Blue Sky", "Robot", "Golden Chain").

**Important Note on Extra Arguments:**

The `extra-inputs` and `extra-argument-types` found in some JSON examples are for advanced use cases where additional custom data types need to be passed to your NFT creation logic. If you choose to include these, they must be added to your `launchpad_mint` or `create_nft` function signatures in the exact order and type expected by the client. The example comments in the code blocks above illustrate how these would appear as function parameters. For basic integration, these can be omitted. Focus on the core arguments specified in the initial function signatures.
#### Example of a json file with extra arguments
```json
[
  {
    "name": "My awesome NFT #1",
    "description": "This colletion will rule the world",
    "imageUrl": "https://example-image-url.com/nft1.png",
    "reserveForCreator": true,
    "attributes": [
      {
        "trait_type": "Background",
        "value": "Blue Sky"
      },
      {
        "trait_type": "Body",
        "value": "Robot"
      },
      {
        "trait_type": "Accessory",
        "value": "Golden Chain"
      }
    ],
    "extra-inputs": [
      {
        "type": "String",
        "vaulue": "Some string data"
      },
      {
        "type": "Bool",
        "vaulue": true
      },
      {
        "type": "u64",
        "vaulue": 900
      }
    ],
    "extra-argument-types": [
      "0x1234::new_module::other_struct",
      "0x5678::another_module::my_struct"
    ]
  },
  {
    "name": "My awesome NFT #2",
    "description": "This colletion will rule the world",
    "imageUrl": "https://example-image-url.com/nft2.png",
    "reserveForCreator": false,
    "attributes": [
      {
        "trait_type": "Eyes",
        "value": "Crazy Eyes"
      },
      {
        "trait_type": "Headwear",
        "value": "Wizard Hat"
      },
      {
        "trait_type": "Expression",
        "value": "Smirking"
      },
      {
        "trait_type": "Environment",
        "value": "Night City"
      }
    ],
    "extra-inputs": [
      {
        "type": "String",
        "vaulue": "Some different string"
      },
      {
        "type": "Bool",
        "vaulue": false
      },
      {
        "type": "u64",
        "vaulue": 1234
      }
    ],
    "extra-argument-types": [
      "0x1234::new_module::other_struct",
      "0x5678::another_module::my_struct"
    ]
  }
]

```


