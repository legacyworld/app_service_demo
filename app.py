import os
import random
import time
import logging
from flask import Flask, jsonify, request, render_template, abort
import redis
from redis.exceptions import ConnectionError, TimeoutError


# 環境変数設定 (変更なし)
REDIS_HOST = os.environ.get("REDIS_HOST")
REDIS_PORT = int(os.environ.get("REDIS_PORT", "6380"))
REDIS_PASSWORD = os.environ.get("REDIS_PASSWORD")

# 確率定義 (変更なし)
SUCCESS_RATE = float(os.environ.get("SUCCESS_RATE", "0.6")) # 成功確率
LATENCY_RATE = float(os.environ.get("LATENCY_RATE", "0.3")) # 遅延確率
ERROR_RATE = 1.0 - SUCCESS_RATE - LATENCY_RATE  # 残りをエラー確率に割り当て
SLOW_SLEEP = float(os.environ.get("SLOW_SLEEP", "0.5"))  # ベースのスリープ時間（秒）
REDIS_LOAD_COUNT = int(os.environ.get("REDIS_LOAD_COUNT", "10000")) # 遅延時に発行するRedisコマンド数
REDIS_KEY_PREFIX = "latency_test_key" # V2のエラーパスで使用

# ロギング設定 (変更なし)
logger = logging.getLogger('werkzeug')
logger.setLevel(logging.ERROR)
logger = logging.getLogger("app")
logger.setLevel(logging.DEBUG)
handler = logging.StreamHandler()
logger.addHandler(handler)

# Redis接続設定 (変更なし)
redis_client = None
if REDIS_HOST:
    try:
        logger.info("Connecting to Redis at %s:%d", REDIS_HOST, REDIS_PORT)
        # Note: socket_connect_timeout=2 added for robustness
        redis_client = redis.Redis(host=REDIS_HOST, port=REDIS_PORT, db=0, socket_connect_timeout=2, password=REDIS_PASSWORD, ssl=True)
        redis_client.ping()
        logger.info("Redis connection successful!")
    except Exception as e:
        logger.error("Redis init failed: %s", e)
else:
    logger.warning("REDIS_HOST not set. Redis client not initialized.")

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)

# CI/CD メタデータ (変更なし)
GIT_COMMIT = os.environ.get("GIT_COMMIT", "unknown")
DEPLOY_ID = os.environ.get("DEPLOY_ID", "unknown")

# =======================================================
# ルート
# =======================================================

@app.route("/")
def index():
    """
    メインのダッシュボードUIを返す
    templates/index.html をレンダリング
    """
    logger.info("Rendering main dashboard UI")
    return render_template(
        "index.html",
        GIT_COMMIT=GIT_COMMIT,
        DEPLOY_ID=DEPLOY_ID
    )

@app.route("/api/status")
def api_status():
    start_time = time.time()
    
    # クエリパラメータからバージョンを取得 ('v2'をデフォルトとする)
    version = request.args.get('version', 'v2').lower() 
    
    outcome = "UNKNOWN"
    status_code = 200
    message = "Status check complete."
    
    # --- V1 Logic (Forced Success) ---
    if version == 'v1':
        outcome = "SUCCESS"
        logger.info("API Hit: V1 - Forced SUCCESS")
        
        # Redisアクセスシミュレーション（成功時のみ）
        if redis_client:
            try:
                redis_client.set("status_key", "ok", ex=60) 
            except (ConnectionError, TimeoutError) as e:
                logger.warning(f"Redis operation failed during V1 path: {type(e).__name__}")
                message = "V1 Success, but Redis temporary unavailable."
        
    # --- V2 Logic (Probabilistic Failure/Latency) ---
    elif version == 'v2':
        r = random.random()
        
        if r < SUCCESS_RATE:
            # V2 Success
            outcome = "SUCCESS"
            logger.info("API Hit: V2 - SUCCESS")
            
            if redis_client:
                try:
                    redis_client.set("status_key", "ok", ex=60) 
                except (ConnectionError, TimeoutError) as e:
                    logger.warning(f"Redis operation failed during V2 SUCCESS path: {type(e).__name__}")
                    message = "V2 Success, but Redis temporary unavailable."
            
        elif r < SUCCESS_RATE + LATENCY_RATE:
            # V2 Latency (Slow)
            outcome = "LATENCY"
            logger.warning("API Hit: V2 - Slow Response Simulation")
            time.sleep(SLOW_SLEEP) # 遅延を適用
            # ★ 修正: f-stringにSLOW_SLEEP変数を指定 ★
            message = f"V2 Artificial delay of {SLOW_SLEEP}s applied."
            
        else:
            # V2 Error (High Redis Load) - 500を発生させる
            outcome = "ERROR"
            status_code = 500
            logger.error(f"API Hit: V2 - High Redis Load Simulation triggered")
            start_redis_load = time.time()
            
            # --- High Load Simulation using Redis ---
            if redis_client:
                try:
#                    pipe = redis_client.pipeline()
                    # REDIS_LOAD_COUNT回、SETコマンドをパイプラインにキューイングする
                    for i in range(REDIS_LOAD_COUNT):
                        # ★ 修正: f-stringにREDIS_KEY_PREFIXとiを指定 ★
                        key = f"{REDIS_KEY_PREFIX}:{i}"
                        redis_client.set(key, "load_data", ex=1) 
#                        pipe.set(key, "load_data", ex=1) 
                    
#                    pipe.execute()
                    redis_load_time = time.time() - start_redis_load
                    # ★ ユーザー要求の特定のエラーメッセージを返す ★
                    message = f"ERROR: High Redis Load: Too many requests (Load took {redis_load_time*1000:.2f}ms)"
                    logger.error("High Redis Load: Too many requests")
                    
                except (ConnectionError, TimeoutError) as e:
                    logger.error(f"Redis load failed: {type(e).__name__}.")
                    message = f"ERROR: High Redis Load Simulation Failed: Redis connection issue ({type(e).__name__})."
                except Exception as e:
                     message = f"ERROR: High Redis Load: Simulation failed ({type(e).__name__})."
            else:
                 message = "ERROR: High Redis Load: Redis client not initialized. Falling back to simple 500 error."
            
            # V2 Error responses must return immediately
            latency_ms = (time.time() - start_time) * 1000
            return jsonify({
                "timestamp": time.time() * 1000,
                "outcome": outcome,
                "latency_ms": latency_ms,
                "error": message,
                "version": version
            }), status_code

    else:
        # 無効なバージョン
        status_code = 400
        outcome = "INVALID_VERSION"
        message = "Invalid version specified. Use v1 or v2."
        
    # --- Standard Response construction (for SUCCESS, LATENCY, INVALID_VERSION) ---
    end_time = time.time()
    latency_ms = (end_time - start_time) * 1000

    response_data = {
        "timestamp": end_time * 1000,
        "outcome": outcome,
        "latency_ms": latency_ms,
        "message": message,
        "commit": GIT_COMMIT,
        "deploy": DEPLOY_ID,
        "version": version, # レスポンスにバージョンを含める
        "redis_active": bool(redis_client)
    }
    
    return jsonify(response_data), status_code

# =======================================================
# 実行
# =======================================================
if __name__ == "__main__":
    # debug=False in production environments
    app.run(host="0.0.0.0", debug=True)