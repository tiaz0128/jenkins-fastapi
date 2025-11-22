pipeline {
    agent any
    
    environment {
        // 배포에 필요한 변수 설정
        DOCKER_IMAGE = "fastapi-app"                    // 도커 이미지 이름
        CONTAINER_NAME = "fastapi-container"            // 도커 컨테이너 이름
        PORT = "8000"                                    // 컨테이너와 연결할 포트
        REMOTE_USER = "ec2-user"                        // 원격 서버 사용자
        REMOTE_HOST = "13.125.199.43"                   // 원격 서버 IP (Public IP)
        REMOTE_DIR = "/home/ec2-user/deploy"            // 원격 서버에 파일 복사할 경로
        SSH_CREDENTIALS_ID = "639c6fb6-f249-4ecb-87bf-fb5e6ff9dbb2" // Jenkins SSH 자격 증명 ID
    }
    
    stages {
        stage('Git Checkout') {
            steps {
                // Jenkins가 연결된 Git 저장소에서 최신 코드 체크아웃
                checkout scm
            }
        }
        
        stage('Prepare Files') {
            steps {
                // 배포에 필요한 파일 확인
                sh '''
                    echo "=== 파일 목록 확인 ==="
                    ls -la
                    echo "=== pyproject.toml 확인 ==="
                    cat pyproject.toml
                '''
            }
        }
        
        stage('Copy to Remote Server') {
            steps {
                // Jenkins가 원격 서버에 SSH 접속할 수 있도록 sshagent 사용
                sshagent (credentials: [env.SSH_CREDENTIALS_ID]) {
                    // 원격 서버에 배포 디렉토리 생성 (없으면 새로 만듦)
                    sh """
                        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
                        ${REMOTE_USER}@${REMOTE_HOST} "mkdir -p ${REMOTE_DIR}"
                    """
                    
                    // 필요한 파일들을 원격 서버에 복사
                    sh """
                        scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
                        Dockerfile pyproject.toml uv.lock ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}/
                    """
                    
                    // src 디렉토리 전체 복사
                    sh """
                        scp -r -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
                        src ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}/
                    """
                }
            }
        }
        
        stage('Remote Docker Build & Deploy') {
            steps {
                sshagent (credentials: [env.SSH_CREDENTIALS_ID]) {
                    sh """
                        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
                        ${REMOTE_USER}@${REMOTE_HOST} << 'ENDSSH'
                            cd ${REMOTE_DIR} || exit 1
                            
                            echo "=== 기존 컨테이너 중지 및 제거 ==="
                            docker rm -f ${CONTAINER_NAME} || true
                            
                            echo "=== Docker 이미지 빌드 ==="
                            docker build -t ${DOCKER_IMAGE} .
                            
                            echo "=== Docker 컨테이너 실행 ==="
                            docker run -d --name ${CONTAINER_NAME} -p ${PORT}:${PORT} ${DOCKER_IMAGE}
                            
                            echo "=== 컨테이너 상태 확인 ==="
                            sleep 3
                            docker ps | grep ${CONTAINER_NAME}
                            
                            echo "=== 헬스체크 ==="
                            for i in {1..10}; do
                                if curl -s -f http://localhost:${PORT}/health > /dev/null; then
                                    echo "✓ 헬스체크 성공!"
                                    exit 0
                                fi
                                echo "재시도 중... (\$i/10)"
                                sleep 2
                            done
                            
                            echo "✗ 헬스체크 실패!"
                            docker logs ${CONTAINER_NAME}
                            exit 1
ENDSSH
                    """
                }
            }
        }
    }
    
    post {
        success {
            echo "✓ 배포 성공! 서버가 http://${REMOTE_HOST}:${PORT} 에서 실행 중입니다."
        }
        failure {
            echo "✗ 배포 실패!"
        }
    }
}
