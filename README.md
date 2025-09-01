# Hokko launchpad


There is two option to setup a launchpad on Hokko. 
The first is to add the launhpad mint function inside of the NFT contract which is the most secure and seamless way. 
The functian that needs to exist in the must be called launchpad_mint and have these arguments implemented in the exact order. 
```move 
public fun launchpad_mint(
    name: String,
    description: String,
    image_url: String,
    tarit_keys: vector<String>,
    value_keys: vector<String>,
    payment: Coin<SUI>,
    clock: &Clock,
    policy: &TransferPolicy<Nft>,
    launch: &mut Launch,
    launchpad: &mut Launchpad,
    ctx: &mut TxContext
) {
// Pass in the value to create your own nft
    let nft: Nft = create_nft();

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
```

this funciton needs to exists and have this exact order if you want extra arguments plese refer to
this. where it contain the logic to assemble your nft and return the nft that we later than put 
into the launchpad

create_nft
```move 
public fun create_nft(
    mint_cap: &MintCap,
    name: String,
    description: String,
    image_url: String,
    tarit_keys: vector<String>,
    value_keys: vector<String>,
): Nft {}
```



Or you implement our launchpad mint function into your own nft contract for better security
and no need for a mintcap





Help me write a guide for collection creators to follow when they build their own NFT contract. the extra arguments in this json file could be omited. 
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


