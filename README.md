# Auto DST (HMG-API mod)

Turns the head unit's Daylight Saving Time switch on and off on the right dates, so the clock
changes by itself in spring and fall.

**[Download the latest release](https://github.com/dibble9012/auto-dst/releases/latest)**

Tested on a 2023 Kia EV6 GT-Line (USA), firmware 260507.

## Install

You need HMG-API 1.0.0 or later on the car first. Both methods use a USB flash drive. Download
the file for your method from the
[latest release](https://github.com/dibble9012/auto-dst/releases/latest), listed under **Assets**.

ADB over USB has to be off, or the port can't read the drive.

### With the HMG-API app

1. Download `auto-dst-v1.0.0-hmgapi-usb.zip`.
2. Unzip it onto the top level of a FAT32 flash drive, so the drive has
   `HMGAPI/updates/auto-dst-v1.0.0.zip`.
3. Plug the drive into the car and install the mod from the updates page in the HMG-API app.
4. Tap **Apply changes** in the app.

To remove the mod, use the HMG-API app.

### With NEMESIS

1. Download `auto-dst-v1.0.0-nemesis-usb.zip`.
2. Unzip it onto the top level of a FAT32 or exFAT flash drive, so the drive has `NEMESIS.data`
   and the `packages` folder at its top level. Keep only one NEMESIS package on the drive.
3. Once Android is up, plug the drive into the car and confirm the install of "Auto DST".
4. Restart the head unit if it asks, then take the drive out.

HMG-API installs and applies the mod for you. To remove it, uninstall the package in NEMESIS
Manager.

## Settings (HMG-API app)

| Setting | Options | Default |
|---|---|---|
| Daylight saving rule | US and Canada, Europe, Never | US and Canada |
| Show a message when the clock changes | on, off | on |

Rule changes apply within a minute. The mod keeps the switch matching the rule, so if you change
the switch by hand in Settings, it goes back within a minute. To control it by hand, disable the
mod.

## How it works

- The switch is `com.hkmc.micom.time` (`ITimePolicyService`), the `TimePolicyManager.setDst()`
  that Settings, Clock calls. Transactions: `3` isDst, `4` setDst(i32), `5` isRealTimeSet.
- The zone stays a fixed offset (`persist.sys.timezone` = `Mobis/UTC-05:00`). With DST on, the
  service runs the system clock one hour ahead, so real UTC is the clock minus an hour.
- `mod/dst.sh` runs as a root service and checks once a minute. It works out real UTC, applies the
  rule, and calls setDst when the switch is wrong. A zone in any other form is left alone.
- Settings, Clock keeps its own copy of the switch (`RegPrefDST.xml` `RegKeyDST`,
  `RegInitValue.xml` `savevalue_dst`). The script rewrites those in place and restarts General
  Settings to match, but not while that screen is open.

The log is at `/data/hmgapi/logs/auto-dst/dst.log`. On the car, `sh dst.sh check [real-UTC-epoch]`
prints what the mod would do and changes nothing.

## Build

You need a checkout of [HMG-API](https://github.com/VysseCodes/HMG-API), whose
`tools/mknemesismod.sh` makes the NEMESIS package.

```bash
./build.py ~/.hmgapi/author.key ../HMG-API
```

This writes the two release files to `dist/`, along with `auto-dst-v1.0.0.hmgapi.zip`, the signed
mod inside them, and `auto-dst-v1.0.0-nemesis-package.zip`, the file to upload to the NEMESIS
Package Store. Updates must be signed with the same key as the first install.

## Test

```bash
test/run.sh
```

This runs the script off the car under bash, with a fake `service` and `getprop`, and checks the
changeover times for the US and Europe rules.

## License

AGPL-3.0. See [LICENSE](LICENSE).
