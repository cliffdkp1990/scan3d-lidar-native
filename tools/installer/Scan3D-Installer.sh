#!/usr/bin/env bash
# Local, interactive installer. No remote commands or background service.
set -euo pipefail
umask 077
readonly ipa_sha='ed1b8e6cfa1640b5d73c42695ceecf02a605e454d3275158fba8791c96f07399'
readonly tool_sha='dbfd9d7216f077c84c171b688c4173c37c23ca76bf7fd185d1a9ae8a53dab59f'
readonly tool="$HOME/.local/share/scan3d-bridge/xtool.AppImage"
die() { printf '\nSTOP: %s\n' "$*" >&2; exit 1; }
yesno() { local reply; read -r -p "$1 [J/N] " reply || return 1; [[ "$reply" == J || "$reply" == j ]]; }
verify() { local actual; actual=$(sha256sum -- "$1") || return 1; [[ "${actual%% *}" == "$2" ]]; }

# A read-only test for an explicitly chosen IPA; never starts an installer.
if [[ "${1:-}" == --verify-ipa ]]; then
    [[ $# == 2 && -f "$2" ]] || die 'IPA-fil mangler.'
    verify "$2" "$ipa_sha" || die 'IPA matcher ikke den godkendte build.'
    echo 'OK: godkendt IPA SHA256.'
    exit 0
fi
[[ $# == 0 ]] || die 'Ukendt argument.'
[[ -t 0 ]] || die 'Start interaktivt fra den lokale Windows-bro.'
[[ "$(uname -m)" == x86_64 ]] || die 'Denne udgave er kun testet for x86_64.'
[[ -f "$tool" && -x "$tool" ]] || die 'Klargor xtool med Scan3D-Lokal-Bro.cmd forst.'
verify "$tool" "$tool_sha" || die 'xtool SHA256 matcher ikke den testede version.'
command -v wslpath >/dev/null || die 'Start inde i WSL2.'
echo 'Scan3D lokal installation - den godkendte IPA fra build fec57d534df8.'
# The all-in-one bundle contains exactly the pinned IPA beside this script.
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
ipa="$script_dir/Scan3D-unsigned.ipa"
echo 'Kontrollerer den medfoelgende IPA. Ingen manuel filsti.'
[[ -f "$ipa" ]] || die 'IPA-fil findes ikke.'
verify "$ipa" "$ipa_sha" || die 'Forkert IPA-version eller beskadiget fil.'
work=$(mktemp -d)
trap 'rm -f -- "$work/Scan3D-unsigned.ipa"; rmdir -- "$work"' EXIT
cp -- "$ipa" "$work/Scan3D-unsigned.ipa"
verify "$work/Scan3D-unsigned.ipa" "$ipa_sha" || die 'Kopien er ikke identisk.'
echo 'OK: IPA og xtool matcher de godkendte SHA256-vaerdier.'

if ! command -v idevice_id >/dev/null || ! command -v idevicepair >/dev/null || ! command -v ideviceinfo >/dev/null || ! command -v usbmuxd >/dev/null; then
    echo 'Der mangler Linux USB-biblioteker fra Ubuntu.'
    yesno 'Installer usbmuxd og libimobiledevice-utils fra Ubuntu?' || die 'Afventer biblioteker.'
    sudo apt-get update
    sudo apt-get install -- usbmuxd libimobiledevice-utils
fi
# Never auto-bind USB devices. Only the user may choose the intended USB device.
echo 'Tilslut og laas iPhone op. Paa Windows skal den vaere delt og tilsluttet til WSL via usbipd.'
echo 'Hvis den ikke findes: usbipd list; vaelg kun iPhone; usbipd bind --busid <BUSID> (administrator); usbipd attach --wsl --busid <BUSID>.'
if ! pgrep -x usbmuxd >/dev/null; then
    yesno 'Start den lokale usbmuxd-tjeneste?' || die 'Afventer USB-tjeneste.'
    sudo service usbmuxd start || die 'USB-tjenesten kunne ikke startes.'
fi
ids=$(idevice_id -l) || die 'USB-forbindelsen virker ikke.'
mapfile -t devices < <(printf '%s\n' "$ids" | sed '/^$/d')
[[ "${#devices[@]}" == 1 ]] || die 'Der skal vaere netop en USB-tilsluttet iPhone. Se USBIPD ovenfor.'
udid="${devices[0]}"
if ! idevicepair -u "$udid" validate; then
    yesno 'Par denne USB-enhed? Tryk Godkend paa iPhone naar den spoerger.' || die 'Parring ikke godkendt.'
    idevicepair -u "$udid" pair || die 'Parring mislykkedes. Gentag ikke uden ny diagnose.'
    idevicepair -u "$udid" validate || die 'Parring kunne ikke verificeres.'
fi
product=$(ideviceinfo -u "$udid" -k ProductType) || die 'Ingen iPhone-handshake.'
[[ "$product" == iPhone15,3 ]] || die 'Enheden er ikke den forventede iPhone 14 Pro Max.'
version=$(ideviceinfo -u "$udid" -k ProductVersion) || die 'iOS-version kunne ikke laeses.'
printf 'OK: iPhone 14 Pro Max, iOS %s. USB-handshake verificeret.\n' "$version"
export APPIMAGE_EXTRACT_AND_RUN=1
echo 'Apple-login foregaar kun lokalt. Gratis xtool-login bruger private Apple-APIer og tredjeparts anisette.'
echo 'Brug helst en separat Apple-konto. Send aldrig kodeord eller 2FA til chatten.'
echo 'Afvis enhver anmodning om at tilbagekalde et eksisterende certifikat.'
yesno 'Vil du starte den lokale Apple-godkendelse og installation nu?' || die 'IPA og USB er klar. Apple-godkendelse afventer.'
"$tool" auth status
if yesno 'Skal xtool logge ind med en Apple-konto nu?'; then
    "$tool" auth login || die 'Apple-login mislykkedes. Ingen gentagelse i denne koersel.'
fi
verify "$work/Scan3D-unsigned.ipa" "$ipa_sha" || die 'IPA blev aendret.'
"$tool" install --usb --udid "$udid" "$work/Scan3D-unsigned.ipa" || die 'Installation ikke godkendt. Gem den konkrete fejl uden personlige oplysninger.'
echo 'xtool meldte succes. Aabn Scan3D paa iPhone; godkend kun den forventede udviklerprofil/Developer Mode ved behov.'
echo 'Fysisk test: kameratilladelse, LiDAR, gem/genaabn, video og PLY/OBJ. Ingen fysisk test er automatisk godkendt.'
