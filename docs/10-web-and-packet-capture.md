# Current web and packet-capture preparation

Updated: 2026-09-08 (Asia/Seoul)

## Current anonymous web observation

- [VERIFIED-DEVICE] Anonymous `GET /` returns HTTP 200 from `httpd/0.9` and a
  page titled `LG U+ CHGW Web`; client-side code loads `/web/intro.html`.
- [VERIFIED-DEVICE] Anonymous `GET /web/intro.html` returns the GAPD-7500 login
  page and references the public JavaScript files captured by
  `scripts/windows/capture-web.ps1`.
- [VERIFIED-DEVICE] An unauthenticated `GET /web/setting_02.html` returns the
  public landing stub rather than upgrade content.
- [VERIFIED-DEVICE] The current public menu script names an `setting_02.html`
  upgrade page, but this does not demonstrate a local firmware-upload endpoint.
- [UNVERIFIED] No authenticated 1.06.08 request trace has been collected.

Only anonymous GETs were issued. No password, captcha answer, session cookie,
configuration form, update check, or firmware request was sent. Raw landing
HTML disclosed device-specific network identifiers, so it was not copied into
Git.

## Helpers and tool state

`capture-web.ps1` fetches only the public landing page and the static assets it
directly references. Raw bodies go under ignored `.work`; the summary excludes
headers such as `Set-Cookie` and records only path, status, type, size, and hash.

`capture-gapd-traffic.ps1` is restricted to the selected Ethernet adapter and a
capture filter of `host 192.168.219.1`. It refuses to start if the adapter is not
Up or cannot be mapped uniquely to a TShark interface. PCAPs go under ignored
`artifacts/pcap` and may never be committed without sanitization.

[VERIFIED-DEVICE] Wireshark, TShark, and Dumpcap are not currently installed, so
no packet capture has run. Installing Npcap adds a packet-capture driver and is
deferred rather than changing the working network stack during the build.
