# 커스텀 빌드 기능 시험

마지막 시험: 2026-09-13 (KST)

시험 대상은 실제 LG-GAPD-7500 한 대입니다. OpenWrt는 SNAPSHOT
`r0-9f62ca8`, 커널은 Linux 6.18.44이며 NAND의 선택된 OpenWrt 슬롯에서
부팅했습니다. 에뮬레이터나 QEMU 결과는 이 표에 넣지 않았습니다.

## 통과한 항목

| 항목 | 확인 방법 | 결과 |
|---|---|---|
| 영구 부팅 | UART를 수신 전용으로 두고 소프트웨어 재부팅 2회 | 두 번 모두 `Boot act=1`에서 OpenWrt 시작 |
| 루트/overlay | `ubus call system board`, `mount`, UBI sysfs | SquashFS root와 UBIFS overlay 사용 |
| NAND 상태 | UBI sysfs | bad PEB 0, 최대 erase counter 3 |
| LAN1 | `ethtool`, SSH/SCP, HTTP | 1 Gbit/s Full Duplex, 오류 0, 양방향 통신 성공 |
| LuCI/uhttpd | 유선 주소를 지정한 `curl` | HTTP 200, 연결 약 1 ms |
| SSH 공개키 | 기존 PC 키로 batch 접속 | 성공 |
| SSH 비밀번호 | 공개키를 끄고 대화형 로그인 | 2026-09-13 실제 로그인 성공. 비밀번호는 기록하지 않음 |
| 기본 서비스 | init 상태와 실제 소켓/규칙 확인 | dnsmasq, dropbear, network, odhcpd, rpcd, uhttpd, wpad 동작 |
| 방화벽 | `nft list ruleset` | firewall4의 `inet fw4` 규칙 로드 |
| Wi-Fi 드라이버 | dmesg, `ubus`, `iw dev` | ath11k, 2.4/5 GHz PHY, 두 AP 인터페이스 생성 성공 |
| LED 제어 | sysfs brightness를 변경하고 원래 값으로 복원 | power, 2.4G, 5G 제어/복원 성공 |
| 온도 센서 | thermal sysfs | 7개 zone, 시험 중 약 38~39 °C |
| sysupgrade 안전장치 | 빌드된 sysupgrade를 `/tmp`에 올려 `sysupgrade -T` | 의도대로 exit 1, GAPD A/B 미검증 메시지와 함께 거부 |
| 순정 슬롯 보존 | 현재 비선택 rootfs의 전체 SHA-256 | 설치 전 백업과 일치 |
| 복구 진입점 | APPSBLENV 원문 확인 | `bootdelay_=1` 유지 |

Windows 쪽에서도 Wi-Fi가 유일한 기본 경로이고, Ethernet 12에는 기본 경로가
없으며, GAPD가 L2에서 확인될 때만 `192.168.219.1/32` 경로가 생기는 것을 다시
확인했습니다. `1.1.1.1:443`은 Wi-Fi, GAPD의 TCP 80/22는 Ethernet 12를 사용했고
세 연결 모두 성공했습니다.

## 일부만 확인한 항목

| 항목 | 확인된 것 | 남은 시험 |
|---|---|---|
| Wi-Fi | 두 radio가 올라오고 2.4 GHz 채널 1, 5 GHz 채널 36에서 AP 인터페이스 생성 | Windows 스캔에서 시험 SSID를 찾지 못함. 별도 클라이언트로 beacon, 연결, DHCP, 실제 전송 확인 필요 |
| USB | Qualcomm DWC3와 xHCI host controller 3개 인식 | USB 메모리/모뎀 연결, 파일 읽기/쓰기 |
| LAN2 | QCA8075 PHY와 포트가 등록됨 | 실제 케이블 링크, DHCP/고정 IP 통신, 장시간 전송 |
| WAN | PHY와 `wan` 인터페이스가 등록됨 | 상위 회선 DHCP, NAT, IPv4/IPv6, 재연결 |
| 버튼 | `gpio_button_hotplug` 모듈 로드 | reset/WPS 버튼을 눌러 hotplug 이벤트 확인 |
| LED | 커널 제어값 변경과 복원 | 실제 케이스에서 색상/포트 매핑 육안 확인 |
| 순정 복귀 | 원본 슬롯과 rollback 스크립트 보존 | BOOTCONFIG 복귀 쓰기와 실제 순정 부팅 |
| 전원 차단 | NAND readback과 일반 재부팅은 통과 | 전원 플러그를 뽑았다 꽂는 cold boot |

Wi-Fi 시험에서는 원본 `/etc/config/wireless`를 `/tmp`에 복사한 뒤 두 시험 AP를
잠깐 만들었습니다. 시험이 끝난 뒤 파일을 원복하고 전후 SHA-256이 같은 것을
확인했습니다. 주변 무선망 이름, BSSID, 장치 MAC은 로그와 이 문서에서 제외했습니다.

## 남아 있는 경고

부팅 약 0.2초 지점에서 아래 계열의 경고가 한 번 발생합니다.

```text
nss_crypto_clk_src: rcg didn't update its configuration
WARNING ... drivers/clk/qcom/clk-rcg2.c ... update_config
```

시험 중 panic, Oops, UBI bad PEB는 없었습니다. 이 경고가 지금 통과한 기능을
깨뜨리는 현상은 보지 못했지만, 원인이 해결된 것은 아닙니다.

## 판정

현재 이미지는 부팅, overlay, LAN1, LuCI/SSH, 방화벽, 무선 PHY/AP 생성까지는
쓸 수 있는 상태입니다. 다만 Wi-Fi 실전송과 WAN/LAN2/USB/버튼을 모두 정상이라고
부를 근거는 아직 없습니다. 그래서 첫 배포는 정식판이 아니라 release candidate로
표시합니다.
