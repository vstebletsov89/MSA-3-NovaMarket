# Для тестирования Rate Limiter

PS C:\tools\nginx> nginx -c conf/rate_limiter.conf -t
nginx: the configuration file C:\tools\nginx/conf/rate_limiter.conf syntax is ok
nginx: configuration file C:\tools\nginx/conf/rate_limiter.conf test is successful

nginx -c conf/rate_limiter.conf

http://localhost/api/web/
{"status": "success", "service": "web_backend", "data": "Web application response"}

http://localhost/api/mobile/
{"status": "success", "service": "mobile_backend", "data": "Mobile application response"}

# Запуск Locust
locust -f rate_limiter.py --host=http://localhost:8080 --web-port=8082

nginx -s stop

-----------------------------
# Для тестирования Circuit Breaker

PS C:\tools\nginx> nginx -c conf/circuit_breaker.conf -t
nginx: the configuration file C:\tools\nginx/conf/circuit_breaker.conf syntax is ok
nginx: configuration file C:\tools\nginx/conf/circuit_breaker.conf test is successful

nginx -c conf/circuit_breaker.conf

# Запуск Locust
locust -f circuit_breaker.py --host=http://localhost:8080 --web-port=8082
