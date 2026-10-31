# Third-party runtime (not stored in git)

`tools/package.py` bundles the UE4SS runtime into the release zip. Put these two archives here before packaging:

| File | SHA-256 | Source |
|---|---|---|
| `UE4SS_v3.0.1-1164-g5e627997.zip` | `3C72142A383E25E9F9553AC9E4D5677AA572E98CB369CAC57200EFB2E381E603` | UE4SS experimental build, as bundled unchanged by DST (`app/resources/solo-mod-runtime/runtime.zip`) |
| `zCustomGameConfigs.zip` | `1B2420B7DEB237CD680D27306EADF26628699D992A322C89A963D80F580C9B78` | UE4SS custom game configs, as bundled unchanged by DST (`app/resources/solo-mod-runtime/configs.zip`) |

Both are MIT-licensed by the UE4SS contributors (https://github.com/UE4SS-RE/RE-UE4SS). The packager checks both hashes before it builds. Upstream's `experimental-latest` release replaces its files over time, which is why the exact tested builds are pinned here.
