#!/bin/bash
set -e

echo "=== FastAPI 배포 시작 ==="

# uv 설치 확인
if ! command -v uv &> /dev/null; then
    echo "uv 설치 중..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
fi

# PATH에 uv 추가
export PATH="$HOME/.local/bin:$PATH"

echo "uv 버전: $(uv --version)"

# 의존성 설치
echo "의존성 설치 중..."
uv sync --frozen --no-cache

# PID 파일 및 로그 파일 경로
PID_FILE="$HOME/fastapi.pid"
LOG_FILE="$HOME/fastapi.log"

# 기존 프로세스 종료
echo "기존 프로세스 종료 중..."
if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE")
    if ps -p $OLD_PID > /dev/null 2>&1; then
        echo "기존 프로세스 종료: PID $OLD_PID"
        kill $OLD_PID || true
        sleep 2
        # 강제 종료가 필요한 경우
        if ps -p $OLD_PID > /dev/null 2>&1; then
            kill -9 $OLD_PID || true
        fi
    fi
fi

# 포트로 프로세스 찾아서 종료 (백업)
pkill -f "uvicorn src.main:app" || true
sleep 1

# 애플리케이션 실행
echo "애플리케이션 실행 중..."
echo "작업 디렉토리: $(pwd)"

# 백그라운드로 실행하고 PID 저장
nohup uv run uvicorn src.main:app --host 0.0.0.0 --port 8000 > "$LOG_FILE" 2>&1 &
APP_PID=$!
echo $APP_PID > "$PID_FILE"

echo "프로세스 ID: $APP_PID"
echo "로그 파일: $LOG_FILE"
sleep 3

# 프로세스 확인
if ! ps -p $APP_PID > /dev/null 2>&1; then
    echo "✗ 프로세스가 시작되지 않았습니다!"
    echo ""
    echo "=== 로그 내용 ==="
    cat "$LOG_FILE"
    exit 1
fi

# 헬스체크
echo ""
echo "=== 헬스체크 중 ==="
MAX_RETRIES=15
for i in $(seq 1 $MAX_RETRIES); do
    if curl -s -f http://localhost:8000/health > /dev/null 2>&1; then
        echo "✓ 헬스체크 성공!"
        echo "✓ 배포 완료! 서버가 http://localhost:8000 에서 실행 중입니다."
        echo ""
        echo "=== 실행 중인 프로세스 ==="
        ps aux | grep "[u]vicorn src.main:app"
        echo ""
        echo "=== 최근 로그 (20줄) ==="
        tail -n 20 "$LOG_FILE"
        exit 0
    fi
    
    # 프로세스가 중간에 종료되었는지 확인
    if ! ps -p $APP_PID > /dev/null 2>&1; then
        echo "✗ 프로세스가 실행 중 종료되었습니다!"
        echo ""
        echo "=== 로그 내용 ==="
        cat "$LOG_FILE"
        exit 1
    fi
    
    echo "재시도 중... ($i/$MAX_RETRIES)"
    sleep 1
done

echo "✗ 헬스체크 실패!"
echo ""
echo "=== 프로세스 상태 ==="
ps aux | grep "[u]vicorn" || echo "uvicorn 프로세스 없음"
echo ""
echo "=== 로그 내용 ==="
cat "$LOG_FILE"
exit 1
