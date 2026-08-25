"""Apply Android permissions, package id, and Firebase google-services hooks.
No secrets are written unless GOOGLE_SERVICES_JSON env is set.
"""
from __future__ import annotations

import json
import os
import re
from pathlib import Path

PACKAGE = "com.signalyab.crypto_signal_scanner"


def main() -> None:
    manifest = Path("android/app/src/main/AndroidManifest.xml")
    text = manifest.read_text(encoding="utf-8")
    for perm in [
        "android.permission.INTERNET",
        "android.permission.ACCESS_NETWORK_STATE",
        "android.permission.POST_NOTIFICATIONS",
        "android.permission.VIBRATE",
        "android.permission.RECEIVE_BOOT_COMPLETED",
    ]:
        if perm not in text:
            marker = "<manifest "
            start = text.find(marker)
            end = text.find(">", start)
            text = (
                text[: end + 1]
                + f'\n    <uses-permission android:name="{perm}" />'
                + text[end + 1 :]
            )

    if "android:usesCleartextTraffic" not in text:
        text = text.replace(
            "<application",
            '<application android:usesCleartextTraffic="true"',
            1,
        )
    text, n = re.subn(
        r'android:label="[^"]*"',
        'android:label="سیگنال‌یاب"',
        text,
        count=1,
    )
    if n != 1:
        raise SystemExit("label not found")

    if "com.google.firebase.messaging.default_notification_channel_id" not in text:
        meta = (
            '    <meta-data\n'
            '            android:name="com.google.firebase.messaging.default_notification_channel_id"\n'
            '            android:value="signalyab_futures_opportunities" />\n'
            "    </application>"
        )
        text = text.replace("</application>", meta, 1)

    manifest.write_text(text, encoding="utf-8")

    res = Path("android/app/src/main/res/xml")
    res.mkdir(parents=True, exist_ok=True)
    (res / "network_security_config.xml").write_text(
        """<?xml version=\"1.0\" encoding=\"utf-8\"?>
<network-security-config>
  <base-config cleartextTrafficPermitted=\"true\">
    <trust-anchors>
      <certificates src=\"system\" />
      <certificates src=\"user\" />
    </trust-anchors>
  </base-config>
  <domain-config cleartextTrafficPermitted=\"true\">
    <domain includeSubdomains=\"true\">tabdeal.org</domain>
    <domain includeSubdomains=\"true\">api1.tabdeal.org</domain>
    <domain includeSubdomains=\"true\">api.tabdeal.org</domain>
    <domain includeSubdomains=\"true\">binance.com</domain>
  </domain-config>
</network-security-config>
""",
        encoding="utf-8",
    )
    m = manifest.read_text(encoding="utf-8")
    if "networkSecurityConfig" not in m:
        m = m.replace(
            "<application",
            '<application android:networkSecurityConfig="@xml/network_security_config"',
            1,
        )
        manifest.write_text(m, encoding="utf-8")

    app_gradle = Path("android/app/build.gradle")
    if not app_gradle.exists():
        app_gradle = Path("android/app/build.gradle.kts")
    g = app_gradle.read_text(encoding="utf-8")
    if "applicationId" in g:
        if "applicationId =" in g:
            g = re.sub(
                r'applicationId\s*=\s*["\'][^"\']+["\']',
                f'applicationId = "{PACKAGE}"',
                g,
                count=1,
            )
        else:
            g = re.sub(
                r'applicationId\s+["\'][^"\']+["\']',
                f'applicationId "{PACKAGE}"',
                g,
                count=1,
            )
    else:
        g = g.replace(
            "defaultConfig {",
            f'defaultConfig {{\n        applicationId "{PACKAGE}"',
            1,
        )
    if "com.google.gms.google-services" not in g:
        g = g.rstrip() + '\n\napply plugin: "com.google.gms.google-services"\n'
    app_gradle.write_text(g, encoding="utf-8")

    root_gradle = Path("android/build.gradle")
    if not root_gradle.exists():
        root_gradle = Path("android/build.gradle.kts")
    if root_gradle.exists():
        rg = root_gradle.read_text(encoding="utf-8")
        if "google-services" not in rg and "dependencies {" in rg:
            rg = rg.replace(
                "dependencies {",
                'dependencies {\n        classpath "com.google.gms:google-services:4.4.2"',
                1,
            )
            root_gradle.write_text(rg, encoding="utf-8")

    settings = Path("android/settings.gradle")
    if settings.exists():
        s = settings.read_text(encoding="utf-8")
        if "com.google.gms.google-services" not in s and "plugins {" in s:
            s = s.replace(
                "plugins {",
                'plugins {\n    id "com.google.gms.google-services" version "4.4.2" apply false',
                1,
            )
            settings.write_text(s, encoding="utf-8")

    gs_path = Path("android/app/google-services.json")
    secret = os.environ.get("GOOGLE_SERVICES_JSON", "").strip()
    if secret:
        gs_path.write_text(secret, encoding="utf-8")
        print("google-services.json from secret (live FCM path)")
    else:
        placeholder = {
            "project_info": {
                "project_number": "0",
                "project_id": "signalyab-placeholder",
                "storage_bucket": "signalyab-placeholder.appspot.com",
            },
            "client": [
                {
                    "client_info": {
                        "mobilesdk_app_id": "1:0:android:deadbeef",
                        "android_client_info": {"package_name": PACKAGE},
                    },
                    "oauth_client": [],
                    "api_key": [{"current_key": "placeholder-not-for-production"}],
                    "services": {
                        "appinvite_service": {"other_platform_oauth_client": []}
                    },
                }
            ],
            "configuration_version": "1",
        }
        gs_path.write_text(json.dumps(placeholder, indent=2), encoding="utf-8")
        print("google-services.json PLACEHOLDER — FCM LIVE = CREDENTIAL REQUIRED")

    print("Android network + notification + Firebase hooks applied")


if __name__ == "__main__":
    main()
