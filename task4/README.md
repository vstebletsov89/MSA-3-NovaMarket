pip install locust
# Для тестирования Rate Limiter
nginx -c /полный/путь/к/task4/rate_limiter.conf

# Запуск Locust
locust -f task4/rate_limiter.py --host=http://localhost:80 --web-port=8082

Откройте http://localhost:8082, задайте ~100 пользователей и hatch rate ~20, запустите тест. Вы увидите 429 ответы при превышении лимита.

nginx -s stop

nginx -c /полный/путь/к/task4/circuit_breaker.conf

# Запуск Locust
locust -f task4/circuit_breaker.py --host=http://localhost:8080 --web-port=8082

Откройте http://localhost:8082, задайте ~30 пользователей, запустите тест. В логах Locust и на дашборде вы увидите:
Сначала ошибки от upstream
Затем fallback-ответы (Circuit Breaker открыт)
Через 30 секунд — восстановление

+скриншоты из Locust UI