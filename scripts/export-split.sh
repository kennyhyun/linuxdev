#!/bin/bash

set -e

SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# 설정
VM_NAME="${1:-linuxdev}"
EXPORT_FORMAT="qcow2"  # qcow2만 지원
OUTPUT_DIR="$PROJECT_DIR/exports"
VOLUME_SIZE="2000m"  # 2GB보다 약간 작게 (안전 마진)

# 함수들
check_vm_status() {
    echo "Checking VM status..."
    if pgrep -f "qemu-system-aarch64" > /dev/null; then
        echo "⚠️  VM is running. Shutting down safely..."
        "$PROJECT_DIR/halt.sh"
        
        # VM 종료 대기
        for i in {1..30}; do
            if ! pgrep -f "qemu-system-aarch64" > /dev/null; then
                echo "✅ VM shutdown complete"
                break
            fi
            if [ $i -eq 30 ]; then
                echo "❌ VM shutdown timeout"
                exit 1
            fi
            sleep 2
        done
    else
        echo "✅ VM is not running"
    fi
}

export_qcow2_uncompressed() {
    local input_file="$PROJECT_DIR/vm/disk.qcow2"
    local output_file="$OUTPUT_DIR/${VM_NAME}-$(date +%Y%m%d).qcow2"
    
    echo "Exporting QCOW2 format (uncompressed)..."
    qemu-img convert -f qcow2 -O qcow2 "$input_file" "$output_file"
    echo "✅ QCOW2 export complete: $output_file"
    echo "$output_file"
}

create_7zip_volumes() {
    local file_path="$1"
    local filename="$(basename "$file_path")"
    local dir="$(dirname "$file_path")"
    local base_name="${filename%.*}"
    
    echo "Creating 7zip volumes (${VOLUME_SIZE} each)..."
    
    # 7zip 설치 확인
    if ! command -v 7z >/dev/null 2>&1; then
        echo "Installing 7zip..."
        if [[ $(uname -s) == "Darwin" ]]; then
            brew install p7zip
        else
            sudo apt-get update && sudo apt-get install -y p7zip-full
        fi
    fi
    
    # 7zip으로 볼륨 분할 압축 (최대 압축률)
    cd "$dir"
    local archive_name="${base_name}"
    # 포맷에 따라 다른 아카이브 이름 사용
    if [[ "$filename" == *.img ]]; then
        archive_name="${base_name}-raw"
    elif [[ "$filename" == *.qcow2 ]]; then
        archive_name="${base_name}"
    fi
    7z a -t7z -v${VOLUME_SIZE} -mx=9 "${archive_name}.7z" "$filename"
    
    # 압축 파일 검증 및 단일 볼륨 처리
    echo "Verifying compressed archive..."
    if 7z t "${archive_name}.7z.001" > /dev/null 2>&1; then
        echo "✅ Archive verification successful"
        
        # 단일 볼륨인 경우 .001 제거
        if [ ! -f "${archive_name}.7z.002" ]; then
            mv "${archive_name}.7z.001" "${archive_name}.7z"
            echo "✅ Renamed single volume to ${archive_name}.7z"
        fi
        
        # 검증 성공 시 원본 파일 자동 삭제
        rm "$file_path"
        echo "✅ Original file deleted after verification"
    else
        echo "❌ Archive verification failed - keeping original file"
        return 1
    fi
    

    
    # 체크섬 파일 생성
    echo "Creating checksums..."
    if [ -f "${archive_name}.7z" ]; then
        # 단일 볼륨
        shasum -a 256 "${archive_name}.7z" > "${archive_name}.sha256"
    else
        # 다중 볼륨
        for vol_file in ${archive_name}.7z.*; do
            if [ -f "$vol_file" ]; then
                shasum -a 256 "$vol_file" >> "${archive_name}.sha256"
            fi
        done
    fi
    
    echo "✅ 7zip archive created:"
    
    # 단일/다중 볼륨에 따른 변수 설정
    local archive_ext=".7z"
    local extract_cmd_suffix=""
    local notes_desc_aux=""
    if [ -f "${archive_name}.7z.001" ]; then
        local archive_ext=".7z.001"
        local extract_cmd_suffix=".*"
        local notes_desc_aux="split into 2GB volumes."
    fi
    
    ls -lh ${archive_name}${archive_ext}
    echo ""
    echo "📁 Files to upload:"
    echo "  - ${archive_name}${archive_ext} (volume file(s))"
    echo "  - ${archive_name}.sha256 (checksum(s))"
    
    echo ""
    echo "💡 GitHub Release upload commands:"
    echo "  gh release create v$(date +%Y%m%d) ${archive_name}${archive_ext} ${archive_name}.sha256 \\"
    echo "    --title 'VM Export $(date +%Y-%m-%d)' \\"
    echo "    --notes 'VM disk image${notes_desc_aux}. Extract with: 7z x ${archive_name}.7z${extract_cmd_suffix}'"
}

# 메인 실행
main() {
    echo "🚀 Starting VM export with 7zip splitting..."
    echo "VM Name: $VM_NAME"
    echo "Format: $EXPORT_FORMAT"
    echo "Volume Size: $VOLUME_SIZE"
    echo "Output: $OUTPUT_DIR"
    
    # 출력 디렉토리 생성
    mkdir -p "$OUTPUT_DIR"
    
    # VM 상태 확인 및 종료
    check_vm_status
    
    # VM 디스크 파일 존재 확인
    if [ ! -f "$PROJECT_DIR/vm/disk.qcow2" ]; then
        echo "❌ VM disk not found: $PROJECT_DIR/vm/disk.qcow2"
        exit 1
    fi
    
    # QCOW2 export
    export_qcow2_uncompressed
    local exported_file="$OUTPUT_DIR/${VM_NAME}-$(date +%Y%m%d).qcow2"
    
    # 파일 정보 출력
    echo ""
    echo "📊 Export Summary:"
    echo "  File: $exported_file"
    echo "  Size: $(du -h "$exported_file" | cut -f1)"
    
    # 7zip 볼륨 생성
    create_7zip_volumes "$exported_file"
    
    echo ""
    echo "✅ Export and splitting complete!"
}

# 사용법 출력
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo "Usage: $0 [VM_NAME] [FORMAT]"
    echo ""
    echo "Arguments:"
    echo "  VM_NAME   VM name (default: linuxdev)"
    echo ""
    echo "Features:"
    echo "  - Exports VM disk in QCOW2 format"
    echo "  - Splits into 2GB 7zip volumes for GitHub Release"
    echo "  - Creates checksums for verification"
    echo "  - Compatible with all virtualization platforms"
    echo ""
    echo "Examples:"
    echo "  $0                    # Export as QCOW2, split with 7zip"
    echo "  $0 myvm              # Export specific VM"
    echo ""
    echo "After upload, users can:"
    echo "  1. Download all .7z.* files"
    echo "  2. Run the extraction script"
    echo "  3. Convert to desired format with qemu-img"
    exit 0
fi

# 메인 실행
main "$@"