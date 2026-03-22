#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE_APP="default"
NAMESPACE_MONITORING="monitoring"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }

# ─────────────────────────────────────────────
# 0. Проверка зависимостей
# ─────────────────────────────────────────────
check_deps() {
    info "Проверка необходимых утилит..."
    for cmd in minikube kubectl helm; do
        if ! command -v "$cmd" &>/dev/null; then
            echo "❌ Утилита '$cmd' не найдена. Установите её и повторите попытку."
            exit 1
        fi
    done
    ok "Все зависимости найдены."
}

# ─────────────────────────────────────────────
# 1. Поднять Minikube
# ─────────────────────────────────────────────
start_minikube() {
    info "Запуск Minikube..."
    if minikube status --format='{{.Host}}' 2>/dev/null | grep -q "Running"; then
        warn "Minikube уже запущен, пропускаем."
    else
        minikube start --memory=4096 --cpus=2 --driver=docker
    fi

    info "Включение metrics-server..."
    minikube addons enable metrics-server
    ok "Minikube готов, metrics-server активирован."
}

# ─────────────────────────────────────────────
# 2. Часть 1: Деплой приложения + HPA по памяти
# ─────────────────────────────────────────────
deploy_app() {
    info "═══════════════════════════════════════════"
    info "  ЧАСТЬ 1: Деплой приложения и HPA по памяти"
    info "═══════════════════════════════════════════"

    info "Применяем Deployment..."
    kubectl apply -f "$SCRIPT_DIR/deployment.yaml"

    info "Применяем Service..."
    kubectl apply -f "$SCRIPT_DIR/service.yaml"

    info "Ожидаем готовности Deployment..."
    kubectl rollout status deployment/scaletestapp --timeout=120s

    info "Применяем HPA по памяти..."
    kubectl apply -f "$SCRIPT_DIR/hpa-memory.yaml"

    ok "Приложение развёрнуто, HPA по памяти настроен."
    echo ""
    kubectl get deployment scaletestapp
    echo ""
    kubectl get pods --show-labels
    echo ""
    kubectl get hpa scaletestapp-hpa-memory
}

# ─────────────────────────────────────────────
# 3. Тестирование HPA по памяти
# ─────────────────────────────────────────────
test_memory_hpa() {
    info "Запуск порт-форвардинга для нагрузочного теста..."
    kubectl port-forward svc/scaletestapp 8080:80 &
    PF_PID=$!
    sleep 2

    info "───────────────────────────────────────────"
    info "Для проверки HPA по памяти запустите locust:"
    info "  python -m locust --host=http://localhost:8080"
    info "Затем откройте http://localhost:8089 и запустите тест."
    info ""
    info "В отдельном терминале:"
    info "  kubectl get hpa scaletestapp-hpa-memory -w"
    info "  kubectl get pods -l app=scaletestapp -w"
    info ""
    info "Для открытия дашборда Kubernetes:"
    info "  minikube dashboard"
    info "───────────────────────────────────────────"

    read -rp "Нажмите Enter"
    kill "$PF_PID" 2>/dev/null || true
}

# ─────────────────────────────────────────────
# 4. Часть 2: Prometheus + HPA по RPS
# ─────────────────────────────────────────────
deploy_prometheus() {
    info "═══════════════════════════════════════════"
    info "  ЧАСТЬ 2: Prometheus и HPA по RPS"
    info "═══════════════════════════════════════════"

    # Удаляем HPA из Части 1, чтобы не было конфликтов
    info "Удаляем HPA по памяти..."
    kubectl delete hpa scaletestapp-hpa-memory --ignore-not-found=true

    # Создаём namespace для мониторинга
    kubectl create namespace "$NAMESPACE_MONITORING" --dry-run=client -o yaml | kubectl apply -f -

    # Добавляем Helm-репозитории
    info "Добавляем Helm-репозитории..."
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo update

    # Устанавливаем kube-prometheus-stack
    info "Устанавливаем kube-prometheus-stack..."
    helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
        --namespace "$NAMESPACE_MONITORING" \
        --values "$SCRIPT_DIR/prometheus-values.yaml" \
        --wait --timeout 5m

    # Применяем ServiceMonitor для нашего приложения
    info "Применяем ServiceMonitor..."
    kubectl apply -f "$SCRIPT_DIR/servicemonitor.yaml"

    ok "Prometheus установлен."
}

deploy_prometheus_adapter() {
    info "Устанавливаем prometheus-adapter..."
    helm upgrade --install prometheus-adapter prometheus-community/prometheus-adapter \
        --namespace "$NAMESPACE_MONITORING" \
        --values "$SCRIPT_DIR/prometheus-adapter-values.yaml" \
        --wait --timeout 5m

    ok "Prometheus Adapter установлен."

    info "Ожидаем регистрации custom metrics API (до 60 сек)..."
    for i in $(seq 1 12); do
        if kubectl get --raw "/apis/custom.metrics.k8s.io/v1beta1" &>/dev/null; then
            ok "Custom Metrics API доступен!"
            break
        fi
        sleep 5
    done
}

deploy_hpa_rps() {
    info "Применяем HPA по RPS..."
    kubectl apply -f "$SCRIPT_DIR/hpa-rps.yaml"

    ok "HPA по RPS настроен."
    echo ""
    kubectl get hpa scaletestapp-hpa-rps
}

# ─────────────────────────────────────────────
# 5. Проверка Prometheus и тест HPA по RPS
# ─────────────────────────────────────────────
test_rps_hpa() {
    info "Запуск порт-форвардинга для Prometheus UI..."
    kubectl port-forward -n "$NAMESPACE_MONITORING" svc/prometheus-kube-prometheus-prometheus 9090:9090 &
    PROM_PF_PID=$!

    info "Запуск порт-форвардинга для приложения..."
    kubectl port-forward svc/scaletestapp 8080:80 &
    APP_PF_PID=$!
    sleep 2

    info "───────────────────────────────────────────"
    info "Prometheus UI доступен: http://localhost:9090"
    info "  → Перейдите в Status → Targets и убедитесь,"
    info "    что scaletestapp-monitor виден и в состоянии UP."
    info "  → В Graph выполните запрос: http_requests_total"
    info ""
    info "Для нагрузочного теста запустите locust:"
    info "  cd $SCRIPT_DIR && locust --host=http://localhost:8080"
    info "Затем откройте http://localhost:8089 и запустите тест."
    info ""
    info "Наблюдайте за масштабированием:"
    info "  kubectl get hpa scaletestapp-hpa-rps -w"
    info "  kubectl get pods -l app=scaletestapp -w"
    info ""
    info "Проверка custom-метрик:"
    info "  kubectl get --raw '/apis/custom.metrics.k8s.io/v1beta1/namespaces/default/pods/*/http_requests_per_second' | jq"
    info "───────────────────────────────────────────"

    read -rp "Нажмите Enter после завершения тестирования Части 2..."
    kill "$PROM_PF_PID" 2>/dev/null || true
    kill "$APP_PF_PID" 2>/dev/null || true
}

# ─────────────────────────────────────────────
# 6. Cleanup
# ─────────────────────────────────────────────
cleanup() {
    info "Очистка ресурсов..."
    kubectl delete hpa scaletestapp-hpa-rps --ignore-not-found=true
    kubectl delete -f "$SCRIPT_DIR/servicemonitor.yaml" --ignore-not-found=true
    kubectl delete -f "$SCRIPT_DIR/service.yaml" --ignore-not-found=true
    kubectl delete -f "$SCRIPT_DIR/deployment.yaml" --ignore-not-found=true
    helm uninstall prometheus-adapter -n "$NAMESPACE_MONITORING" 2>/dev/null || true
    helm uninstall prometheus -n "$NAMESPACE_MONITORING" 2>/dev/null || true
    kubectl delete namespace "$NAMESPACE_MONITORING" --ignore-not-found=true
    ok "Готово."
}

# ─────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────
main() {
    echo ""
    echo "╔═══════════════════════════════════════════════════════╗"
    echo "║    Масштабирование под нагрузку                       ║"
    echo "╚═══════════════════════════════════════════════════════╝"
    echo ""

    check_deps
    start_minikube

    # Часть 1
    deploy_app
    test_memory_hpa

    # Часть 2
    deploy_prometheus
    deploy_prometheus_adapter
    deploy_hpa_rps
    test_rps_hpa

    echo ""
    info "Все шаги завершены!"
    read -rp "Хотите очистить все ресурсы? (y/n): " ans
    if [[ "$ans" == "y" ]]; then
        cleanup
    fi
}

# ─────────────────────────────────────────────
# Диспетчер команд
# ─────────────────────────────────────────────
case "${1:-}" in
    part1)
        info "Запуск Части 1: Деплой приложения + HPA по памяти"
        check_deps
        start_minikube
        deploy_app
        test_memory_hpa
        ;;
    part2)
        info "Запуск Части 2: Prometheus + HPA по RPS"
        check_deps
        start_minikube
        deploy_prometheus
        deploy_prometheus_adapter
        deploy_hpa_rps
        test_rps_hpa
        ;;
    cleanup)
        cleanup
        ;;
    *)
        main
        ;;
esac