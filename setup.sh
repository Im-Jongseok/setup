#!/bin/bash
# =============================================================================
# Intel iMac 환경 초기 세팅 스크립트 (sudo 권한 불필요)
# 매주 월요일 클렌징 후 실행
# 사용법: bash setup.sh
# =============================================================================

set -e

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC} $1"; }
ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
fail()  { echo -e "${RED}[FAIL]${NC} $1"; }

# =============================================================================
# 앱 설치 (~/Applications)
# =============================================================================

APP_DIR="$HOME/Applications"
mkdir -p "$APP_DIR"
TMPDIR_SETUP=$(mktemp -d)

install_dmg_app() {
    local name=$1
    local url=$2
    local app_name=$3
    if [ -d "$APP_DIR/$app_name" ] || [ -d "/Applications/$app_name" ]; then
        ok "$name 이미 설치됨"
        return
    fi
    info "$name 다운로드 중..."
    local dmg_path="$TMPDIR_SETUP/$name.dmg"
    curl -fsSL -o "$dmg_path" "$url" || { warn "$name 다운로드 실패"; return; }
    local mount_point=$(hdiutil attach "$dmg_path" -nobrowse -quiet 2>/dev/null | tail -1 | awk '{print $NF}')
    if [ -z "$mount_point" ]; then
        # mount point가 경로에 공백이 있을 경우
        mount_point=$(hdiutil attach "$dmg_path" -nobrowse -quiet 2>/dev/null | tail -1 | cut -f3-)
    fi
    if [ -d "$mount_point/$app_name" ]; then
        cp -R "$mount_point/$app_name" "$APP_DIR/" && ok "$name 설치 완료 ($APP_DIR)" || warn "$name 복사 실패"
    else
        warn "$name: 마운트된 볼륨에서 $app_name을 찾을 수 없습니다"
    fi
    hdiutil detach "$mount_point" -quiet 2>/dev/null
    rm -f "$dmg_path"
}

install_zip_app() {
    local name=$1
    local url=$2
    local app_name=$3
    if [ -d "$APP_DIR/$app_name" ] || [ -d "/Applications/$app_name" ]; then
        ok "$name 이미 설치됨"
        return
    fi
    info "$name 다운로드 중..."
    local zip_path="$TMPDIR_SETUP/$name.zip"
    curl -fsSL -o "$zip_path" "$url" || { warn "$name 다운로드 실패"; return; }
    unzip -q "$zip_path" -d "$APP_DIR" && ok "$name 설치 완료 ($APP_DIR)" || warn "$name 압축 해제 실패"
    rm -f "$zip_path"
}

# iTerm2
install_zip_app "iTerm2" "https://iterm2.com/downloads/stable/iTerm2-3_5_13.zip" "iTerm.app"

rm -rf "$TMPDIR_SETUP"

# =============================================================================
# Oh My Zsh 설치
# =============================================================================
info "Oh My Zsh 설치 중..."
if [ -d "$HOME/.oh-my-zsh" ]; then
    ok "Oh My Zsh 이미 설치됨"
else
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    ok "Oh My Zsh 설치 완료"
fi

# =============================================================================
# Zsh 플러그인 설치
# =============================================================================

ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

install_zsh_plugin() {
    local name=$1
    local repo=$2
    local dest="$ZSH_CUSTOM/plugins/$name"
    if [ -d "$dest" ]; then
        ok "zsh 플러그인 '$name' 이미 설치됨"
    else
        info "zsh 플러그인 '$name' 설치 중..."
        git clone --depth=1 "$repo" "$dest" && ok "'$name' 설치 완료" || warn "'$name' 설치 실패"
    fi
}

install_zsh_plugin "zsh-autosuggestions" "https://github.com/zsh-users/zsh-autosuggestions.git"
install_zsh_plugin "zsh-syntax-highlighting" "https://github.com/zsh-users/zsh-syntax-highlighting.git"

# =============================================================================
# .zshrc 설정
# =============================================================================

info ".zshrc 플러그인 설정 중..."
ZSHRC="$HOME/.zshrc"
if [ -f "$ZSHRC" ]; then
    if grep -q "^plugins=" "$ZSHRC"; then
        sed -i '' 's/^plugins=(.*/plugins=(git zsh-autosuggestions zsh-syntax-highlighting)/' "$ZSHRC"
        ok ".zshrc 플러그인 설정 업데이트 완료"
    fi
else
    warn ".zshrc 파일을 찾을 수 없습니다"
fi

# =============================================================================
#  macOS Gureum 한글 입력기 (2벌식) 활성화 
# =============================================================================

setup_korean_input() {
    info "한글 입력기 설정 중..."

    # macOS 기본 bash(3.2)는 $() 명령 치환 안의 heredoc을 파싱하지 못하므로
    # Swift 코드를 임시 파일로 내보낸 뒤 실행한다.
    local swift_dir
    swift_dir=$(mktemp -d)
    local swift_file="$swift_dir/korean_input.swift"

    cat > "$swift_file" <<'SWIFT'
import Carbon
import Foundation
let parentID = "org.youknowone.inputmethod.Korean"
let modeID = "org.youknowone.inputmethod.Gureum.han2"
let gureumPrefix = "org.youknowone.inputmethod.Gureum."

func sources(_ id: String?, includeAll: Bool) -> [TISInputSource] {
    let filter = id.map { [kTISPropertyInputSourceID: $0] as CFDictionary }
    return (TISCreateInputSourceList(filter, includeAll)?
        .takeRetainedValue() as? [TISInputSource]) ?? []
}
func sourceID(_ s: TISInputSource) -> String {
    guard let p = TISGetInputSourceProperty(s, kTISPropertyInputSourceID) else { return "" }
    return Unmanaged<CFString>.fromOpaque(p).takeUnretainedValue() as String
}

// 1) han2가 없으면 부모 한글 입력기를 켠다.
if sources(modeID, includeAll: false).isEmpty,
   let parent = sources(parentID, includeAll: true).first {
    TISEnableInputSource(parent)
    RunLoop.current.run(until: Date().addingTimeInterval(5))
}

// 2) 로마자보다 han2를 먼저 선택한다.
//    현재 선택된 입력 소스는 TISDisableInputSource로 끌 수 없기 때문.
var selected = "not-enabled"
if let han2 = sources(modeID, includeAll: false).first {
    selected = TISSelectInputSource(han2) == noErr ? "ok" : "select-failed"
    RunLoop.current.run(until: Date().addingTimeInterval(1))
}

// 3) han2를 제외한 Gureum 하위 모드(로마자/쿼티 등)를 ID로 찾아 전부 비활성화한다.
//    includeAll:false = 현재 켜져 있는 소스만 대상.
var disabled: [String] = []
for s in sources(nil, includeAll: false) {
    let id = sourceID(s)
    if id.hasPrefix(gureumPrefix) && id != modeID {
        if TISDisableInputSource(s) == noErr { disabled.append(id) }
    }
}
print(selected + " disabled:" + (disabled.isEmpty ? "none" : disabled.joined(separator: ",")))
SWIFT

    local result
    result=$(swift "$swift_file" 2>/dev/null) || result="swift-failed"
    rm -rf "$swift_dir"

    case "$result" in
        ok*)         ok "한글 입력기(2벌식) 설정 완료 (${result#ok })" ;;
        not-enabled*) warn "한글 입력기를 활성화하지 못했습니다 (Gureum 설치 여부 확인)" ;;
        *)           warn "한글 입력기 설정 실패: $result" ;;
    esac
}

setup_korean_input

# =============================================================================
# Spotlight 단축키 초기화
# =============================================================================

info "Spotlight 단축키 초기화 중..."

defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 64 '
<dict>
    <key>enabled</key><true/>
    <key>value</key><dict>
        <key>parameters</key><array>
            <integer>65535</integer><integer>49</integer><integer>1048576</integer>
        </array>
        <key>type</key><string>standard</string>
    </dict>
</dict>'

# 재로그인 없이 즉시 반영 (symbolichotkeys 설정 다시 로드)
ACTIVATE_SETTINGS="/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings"
if [ -x "$ACTIVATE_SETTINGS" ]; then
    "$ACTIVATE_SETTINGS" -u 2>/dev/null \
        && ok "Spotlight 단축키 즉시 반영 완료" \
        || warn "Spotlight 단축키 즉시 반영 실패 (재로그인 시 적용됨)"
else
    warn "activateSettings를 찾을 수 없어 즉시 반영 생략 (재로그인 시 적용됨)"
fi

ok "Spotlight 단축키 기본값 복원 완료"

# =============================================================================
# CapsLock → Fn 매핑 (한영 전환)
# =============================================================================

info "키보드 한영 전환 설정 중..."

# CapsLock → Fn(Globe) 매핑 정의 (즉시 적용 + LaunchAgent 양쪽에서 재사용)
# 0xFF00000003 = Apple 벤더 정의 Fn/Globe 키. AppleFnUsageType=1과 함께
# 동작해야 CapsLock 한 번에 입력 소스(한/영)가 전환됨.
CAPSLOCK_TO_FN='{"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":0x700000039,"HIDKeyboardModifierMappingDst":0xFF00000003}]}'
hidutil property --set "$CAPSLOCK_TO_FN"

# Fn 키 동작을 "입력 소스 변경"으로 설정
defaults write com.apple.HIToolbox AppleFnUsageType -int 1

# CapsLock 딜레이 제거
hidutil property --set '{"CapsLockDelayOverride":0}' 2>/dev/null \
    && ok "CapsLock 딜레이 제거 완료" \
    || warn "CapsLock 딜레이 설정 실패"

# LaunchAgent로 재부팅 후에도 유지
LAUNCH_AGENT_DIR="$HOME/Library/LaunchAgents"
LAUNCH_AGENT_PLIST="$LAUNCH_AGENT_DIR/com.example.KeyRemapping.plist"
mkdir -p "$LAUNCH_AGENT_DIR"

cat > "$LAUNCH_AGENT_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.example.KeyRemapping</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/hidutil</string>
        <string>property</string>
        <string>--set</string>
        <string>${CAPSLOCK_TO_FN}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
PLIST

ok "LaunchAgent 설정 완료: $LAUNCH_AGENT_PLIST"

# =============================================================================
# Dock 설정
# =============================================================================

info "Dock 설정 중..."

defaults write com.apple.dock show-recents -bool false
defaults write com.apple.dock persistent-apps -array
killall Dock 2>/dev/null || true

ok "Dock 설정 완료 (최근 앱 숨김, 기본 앱 제거)"

# =============================================================================
# 마우스 자연스러운 스크롤 끄기
# =============================================================================

info "마우스 스크롤 설정 중..."
defaults write NSGlobalDomain com.apple.swipescrolldirection -bool false
ok "자연스러운 스크롤 비활성화 완료 (재로그인 후 적용)"

# =============================================================================
# Git 기본 설정
# =============================================================================

info "Git 설정 중..."
git config --global user.name "Im-Jongseok"
git config --global user.email "im.jongseoklee@gmail.com"
git config --global init.defaultBranch main
ok "Git 설정 완료"