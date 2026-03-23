# Для тестирования Rate Limiter

PS C:\tools\nginx> nginx -c conf/rate_limiter.conf -t
nginx: the configuration file C:\tools\nginx/conf/rate_limiter.conf syntax is ok
nginx: configuration file C:\tools\nginx/conf/rate_limiter.conf test is successful

nginx -c conf/rate_limiter.conf

localhost:

Welcome to nginx!
If you see this page, the nginx web server is successfully installed and working. Further configuration is required.

For online documentation and support please refer to nginx.org.
Commercial support is available at nginx.com.

Thank you for using nginx.

http://localhost/api/web/
{"status": "success", "service": "web_backend", "data": "Web application response"}

http://localhost/api/mobile/
{"status": "success", "service": "mobile_backend", "data": "Mobile application response"}

# Запуск Locust
locust -f task4/rate_limiter.py --host=http://localhost:80 --web-port=8082

Откройте http://localhost:8082, задайте ~100 пользователей и hatch rate ~20, запустите тест. Вы увидите 429 ответы при превышении лимита.


nginx -s stop

-----------------------------
nginx -s stop






# Запуск Locust
locust -f task4/circuit_breaker.py --host=http://localhost:8080 --web-port=8082

Откройте http://localhost:8082, задайте ~30 пользователей, запустите тест. В логах Locust и на дашборде вы увидите:
Сначала ошибки от upstream
Затем fallback-ответы (Circuit Breaker открыт)
Через 30 секунд — восстановление

+скриншоты из Locust UI