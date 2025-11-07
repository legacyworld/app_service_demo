#!/bin/bash

# =======================================================
# .ENV ファイルの読み込み
# =======================================================

# .env ファイルが存在する場合、内容を環境変数として読み込む
if [ -f .env ]; then
    echo "--- .envファイルを読み込み、環境変数を設定中 ---"
    # whileループを使用して、コメント行と空行をスキップし、
    # 残りのKEY=VALUE形式の行を export する
    while IFS= read -r line || [[ -n "$line" ]]; do
        # コメント行 (#) または空行をスキップ
        [[ "$line" =~ ^#.* ]] && continue
        [[ -z "$line" ]] && continue
        
        # 変数をエクスポート (例: export RESOURCE_GROUP="takeo")
        export "$line"
    done < .env
else
    echo "エラー: .envファイルが見つかりません。処理を中断します。" >&2
    exit 1
fi

echo "=== Redis のファイアウォールルールを取得 ==="
RULES=$(az redis firewall-rules list \
    --name $REDIS_NAME \
    --resource-group $REDIS_RG \
    --query "[].name" -o tsv)

echo "取得したルール: $RULES"

echo "=== すべてのルールを削除 ==="
for rule in $RULES; do
    echo "Deleting rule: $rule"
    az redis firewall-rules delete \
        --name $REDIS_NAME \
        --resource-group $REDIS_RG \
        --rule-name $rule
done

echo "✅ Redis ファイアウォールルールをすべて削除しました"

echo "=== Web App のアウトバウンドIPを取得 ==="
WEBAPP_IPS=$(az webapp show \
    --name $WEBAPP_NAME \
    --resource-group $WEBAPP_RG \
    --query possibleOutboundIpAddresses \
    -o tsv)

echo "取得したIP: $WEBAPP_IPS"

echo "=== Redis ファイアウォールにIPを追加 ==="
for ip in $(echo $WEBAPP_IPS | tr "," "\n"); do
    RULE_NAME="allowWebApp_$(echo $ip | tr '.' '_')"  # ピリオドをアンダースコアに変換
    echo "Adding IP $ip with rule name $RULE_NAME..."
    az redis firewall-rules create \
        --name $REDIS_NAME \
        --resource-group $REDIS_RG \
        --rule-name $RULE_NAME \
        --start-ip $ip \
        --end-ip $ip
done

echo "✅ 完了: Web App のIPをRedisに許可しました"