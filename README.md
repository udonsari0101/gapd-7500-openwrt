# GAPD-7500 OpenWrt

집에 남아 있던 LG U+ GAPD-7500 한 대로 시작한 OpenWrt 포팅입니다.
공식 OpenWrt 소스에 GAPD-7500 지원 패치를 얹어 빌드했고, 실제 기기에서
RAM 부팅과 NAND 설치까지 확인했습니다.

아직 아무 기기에서나 눌러 쓸 수 있는 설치기는 아닙니다. 제가 시험한 기기는
Davolink GAPD-7500, 순정 펌웨어 1.06.08입니다. 보드 리비전이나 파티션 구성이
다르면 멈추는 게 정상입니다. UART와 원본 백업 없이 factory 이미지를 쓰지
마세요.

## 지금 확인된 상태

| 항목 | 결과 |
|---|---|
| OpenWrt 부팅 | NAND에서 자동 부팅, 소프트웨어 재부팅 2회 확인 |
| 루트 파일시스템 | SquashFS + UBIFS overlay 정상 |
| LAN1 | 1 Gbit/s 링크, LuCI/SSH 통신 정상 |
| 관리 페이지 | 시험 기기에서 LAN을 `.219.1`로 바꾼 뒤 `http://192.168.219.1/` HTTP 200 |
| SSH | 공개키 인증과 비밀번호 인증 모두 확인 |
| 방화벽 | firewall4/nftables 규칙 로드 확인 |
| 2.4/5 GHz | ath11k 로드, 두 PHY와 AP 인터페이스 생성 확인 |
| Wi-Fi 실사용 | 외부 기기에서 beacon/연결/전송은 아직 미확인 |
| LED | power/2.4G/5G sysfs 제어 후 원상복구 확인 |
| USB | xHCI 컨트롤러 3개 인식, 실제 USB 장치 시험은 안 함 |
| LAN2/WAN | PHY 인식, 케이블 통신과 WAN DHCP/NAT는 아직 미확인 |
| 버튼 | gpio button 드라이버 로드, 실제 버튼 입력은 아직 미확인 |
| sysupgrade | 일부러 차단됨. `sysupgrade -T`가 거부하는 것까지 확인 |
| 순정 복귀 | 원본 슬롯 보존, 복귀 스크립트 준비. 실제 복귀 부팅은 미확인 |

부팅 초기에 `nss_crypto_clk_src` 관련 커널 경고가 한 번 나옵니다. 지금까지
확인한 LAN, LuCI, SSH, 무선 PHY 동작에는 문제가 없었지만 해결된 경고는
아닙니다. 전체 시험 기록은 [기능 시험표](docs/14-custom-build-test-report.md)에
정리했습니다.

새 initramfs/factory의 첫 LAN 주소는 OpenWrt 기본값인 `192.168.1.1`입니다.
`192.168.219.1`은 시험 기기에서 설치 뒤 따로 저장한 주소입니다.
`192.168.0.1`은 이 빌드의 기본 주소가 아닙니다.

## 어떤 파일을 받으면 되나

[Releases](https://github.com/udonsari0101/gapd-7500-openwrt/releases)에서 두 파일을
배포합니다.

- `...initramfs-uImage.itb`: 먼저 RAM에서 시험 부팅할 파일
- `...squashfs-factory.ubi`: RAM 부팅에 성공한 뒤 비활성 rootfs 슬롯에 쓸 파일

`sysupgrade.bin`은 배포하지 않습니다. 현재 포트는 A/B 전환과 복구를 일반
sysupgrade에 맡길 만큼 검증되지 않았고, 기기 안에서도 GAPD-7500 sysupgrade를
거부하게 해 두었습니다.

다운로드 뒤에는 `SHA256SUMS`와 먼저 비교하세요.

```powershell
Get-FileHash .\openwrt-qualcommax-ipq60xx-lg_gapd-7500-initramfs-uImage.itb -Algorithm SHA256
Get-FileHash .\openwrt-qualcommax-ipq60xx-lg_gapd-7500-squashfs-factory.ubi -Algorithm SHA256
```

확인된 해시는 다음과 같습니다.

| 파일 | 크기 | SHA-256 |
|---|---:|---|
| initramfs ITB | 14,802,824 | `7618dda664005f2360bc786565bf8d4e69a2f5532739df39a0817515607f5400` |
| factory UBI | 13,762,560 | `fe306d8fab0eb96c47649dadd3ee9fb731bdbbbcb587a45a5a8f00722edb892b` |

factory UBI를 순정 웹 업그레이드 화면에 넣으면 안 됩니다. 그 화면은 LG/Davolink
서명 패키지를 기대하며, 여기 있는 ITB/UBI 형식과 맞지 않습니다.

## 준비물

- 3.3 V TTL USB-UART 어댑터
- PC와 공유기를 직접 연결할 유선 랜
- TFTP를 실행할 Windows 또는 Linux PC
- 기기에서 읽어 낸 원본 MTD 백업을 보관할 별도 저장 공간

UART는 GND, TX, RX 세 선만 연결합니다. 어댑터 TX는 공유기 RX로, 어댑터 RX는
공유기 TX로 교차 연결합니다. VCC는 연결하지 않습니다. 콘솔 설정은
115200 8N1입니다.

## 설치 순서

큰 흐름은 아래와 같습니다.

1. 순정 상태에서 모델, 펌웨어 버전, MTD/UBI 구성을 기록합니다.
2. 최소 `mtd0`부터 `mtd18`까지 PC로 백업하고 기기/PC 양쪽 SHA-256을 비교합니다.
3. UART에서 U-Boot 복구 진입이 되는지 먼저 확인합니다.
4. initramfs를 `0x44000000`에 TFTP로 올리고
   `bootm 0x44000000#config@cp03-c1`로 RAM 부팅합니다.
5. PC를 `192.168.1.100/24`로 두고 기본 주소 `192.168.1.1`에서 LAN, SSH,
   ART/caldata, 두 rootfs 슬롯을 다시 확인합니다.
6. factory UBI는 현재 사용하지 않는 슬롯에만 씁니다.
7. 새 슬롯을 한 번 수동 부팅해 확인한 다음에만 BOOTCONFIG를 전환합니다.

실제 기기에서 사용한 명령과 해시는 [RAM 부팅 기록](docs/12-official-openwrt-ram-boot.md),
[영구 설치 기록](docs/13-persistent-openwrt-install.md),
[백업/복구 조건](docs/08-backup-and-recovery.md)에 남겨 두었습니다.

`scripts/device`의 쓰기 스크립트는 시험 기기의 해시를 박아 둔 안전장치입니다.
다른 GAPD-7500에서 그대로 실행했을 때 해시 오류로 멈추면 우회하지 마세요.
그 기기의 백업과 파티션 배치를 먼저 검토해야 합니다. 현재는 RAM 부팅까지를
공통 절차로 보고, NAND 설치는 기기별 확인이 필요한 단계로 봅니다.

## Windows에서 주소가 겹칠 때

설치 뒤 GAPD의 LAN을 직접 `192.168.219.1`로 바꿨고 기존 Wi-Fi 공유기도 같은
주소를 쓴다면 Windows가 엉뚱한 쪽으로 접속하기 쉽습니다. 그 경우에만
`scripts/windows`의 watcher를 사용합니다. 인터넷 기본 경로는 Wi-Fi에 남겨
두고, GAPD가 실제로 연결된 동안에만 `192.168.219.1/32`를 유선으로 보냅니다.
케이블이 빠지면 그 경로부터 지웁니다. 첫 부팅 기본값 `192.168.1.1`을 그대로
쓸 때는 이 중복 주소용 watcher가 필요하지 않습니다.

```powershell
.\scripts\windows\enable-gapd-network-admin.bat
.\scripts\windows\get-gapd-network-status.ps1
```

원복은 다음 파일로 합니다.

```powershell
.\scripts\windows\disable-gapd-network-admin.bat
```

상세 사용법과 네 가지 케이블 연결 시험은
[`scripts/windows/README.md`](scripts/windows/README.md)에 있습니다.

## 직접 빌드하기

WSL2의 Linux 파일시스템에서 빌드하는 것을 권합니다. 소스, feeds, 패치, 설정은
모두 고정돼 있습니다. 스크립트는 FIT/BDF/파티션 크기를 검사하고 새 빌드의
크기와 SHA-256을 출력합니다.

```bash
./scripts/build/build-openwrt-gapd-7500.sh
```

결과는 `artifacts/openwrt-gapd-7500-release`에 생깁니다. APK 압축 메타데이터
때문에 새 빌드가 실기기 시험본과 바이트 단위로 같지 않을 수 있으므로,
Releases에는 별도로 해시 고정한 시험본만 올립니다. GitHub Actions에서도 같은
스크립트를 실행합니다. 자세한 빌드 기준은
[`docs/06-openwrt-build.md`](docs/06-openwrt-build.md)를 참고하세요.

## 참고

숨겨진 순정 웹 경로와 확인된 취약점은
[`docs/11-hidden-web-and-security-audit.md`](docs/11-hidden-web-and-security-audit.md)에
따로 정리했습니다. 비밀번호, 세션, MAC, 원본 플래시 덤프, 기기별 calibration은
저장소와 릴리스에 넣지 않았습니다.

초기 포팅 때 LiBwrt의 IPQ60xx 작업을 참고했고, 지금 배포하는 이미지는 공식
OpenWrt 트리의 고정 커밋에 이 저장소의 GAPD-7500 패치를 적용해 빌드합니다.
문제가 생기면 기기 리비전, 순정 펌웨어 버전, 어느 단계에서 멈췄는지와 함께
이슈를 남겨 주세요. 비밀번호와 원본 ART/MTD 덤프는 첨부하지 마세요.
