from manifest import LoveACEManifest


def test_old_manifest_without_windows_package_parses():
    manifest = LoveACEManifest.model_validate(
        {
            "ota": {
                "content": "update",
                "changelog": [{"version": "1.1.12", "changes": "fix"}],
                "windows": {
                    "version": "1.1.12",
                    "force_ota": False,
                    "url": "https://example.com/loveace.exe",
                    "md5": "old-md5",
                    "type": "native",
                },
                "android": {
                    "version": "1.1.12",
                    "force_ota": False,
                    "url": "https://example.com/app.apk",
                    "md5": "android-md5",
                    "type": "native",
                },
            }
        }
    )

    assert manifest.ota is not None
    assert manifest.ota.windows is not None
    assert manifest.ota.windows.sha256 is None
    assert manifest.ota.windows.package is None
    assert manifest.ota.android is not None
    assert manifest.ota.android.url == "https://example.com/app.apk"


def test_new_windows_package_fields_parse_without_touching_android():
    manifest = LoveACEManifest.model_validate(
        {
            "ota": {
                "content": "update",
                "changelog": [{"version": "1.1.12", "changes": "fix"}],
                "windows": {
                    "version": "1.1.12",
                    "force_ota": False,
                    "url": "https://example.com/loveace.exe",
                    "md5": "old-md5",
                    "sha256": "installer-sha",
                    "type": "native",
                    "package": {
                        "url": "https://example.com/loveace.zip",
                        "sha256": "package-sha",
                        "enabled": False,
                    },
                },
                "android": {
                    "version": "1.1.12",
                    "force_ota": False,
                    "url": "https://example.com/app.apk",
                    "md5": "android-md5",
                    "type": "native",
                },
            }
        }
    )

    assert manifest.ota is not None
    assert manifest.ota.windows is not None
    assert manifest.ota.windows.sha256 == "installer-sha"
    assert manifest.ota.windows.package is not None
    assert manifest.ota.windows.package.enabled is False
    assert manifest.ota.android is not None
    assert manifest.ota.android.package is None


if __name__ == "__main__":
    test_old_manifest_without_windows_package_parses()
    test_new_windows_package_fields_parse_without_touching_android()
    print("python manifest contract tests passed")
