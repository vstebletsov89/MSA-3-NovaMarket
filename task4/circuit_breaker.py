from locust import HttpUser, task, between, events
import logging
import time

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("circuit_breaker_test")


class CircuitBreakerUser(HttpUser):
    """
    Тестирование Circuit Breaker для логистического сервиса.

    Сценарий:
    1. Сначала отправляем нормальные запросы (fast) — всё ОК
    2. Затем шлём ошибочные запросы (error) — после 5 ошибок Circuit Breaker открывается
    3. Проверяем, что возвращается fallback-ответ (503 с JSON)
    4. Ждём 30 секунд — Circuit Breaker закрывается, сервис восстанавливается
    """
    wait_time = between(0.5, 1)

    @task(3)
    def normal_request(self):
        """Нормальный запрос к логистическому сервису"""
        with self.client.get(
            "/logistics/?type=fast",
            name="[CB] Normal request (fast)",
            catch_response=True,
        ) as response:
            if response.status_code == 200:
                try:
                    data = response.json()
                    if data.get("fallback"):
                        logger.warning(
                            "CIRCUIT BREAKER OPEN — got fallback on normal request"
                        )
                        response.failure("Circuit breaker is open (fallback)")
                    else:
                        response.success()
                except Exception:
                    response.success()
            elif response.status_code == 503:
                logger.warning(
                    "CIRCUIT BREAKER OPEN — 503 on normal request"
                )
                response.failure("Circuit breaker is open (503)")
            else:
                response.failure(f"Unexpected status: {response.status_code}")

    @task(5)
    def error_request(self):
        """Запрос, провоцирующий ошибку — для срабатывания Circuit Breaker"""
        with self.client.get(
            "/logistics/?type=error",
            name="[CB] Error request (trigger CB)",
            catch_response=True,
        ) as response:
            if response.status_code == 503:
                try:
                    data = response.json()
                    if data.get("fallback"):
                        logger.info(
                            "CIRCUIT BREAKER OPEN — fallback response received!"
                        )
                        response.failure("CB open - fallback response")
                    else:
                        response.failure("Error from upstream (expected)")
                except Exception:
                    response.failure("Error from upstream (expected)")
            elif response.status_code == 500:
                response.failure("Error from upstream 500 (expected)")
            elif response.status_code == 200:
                response.success()
            else:
                response.failure(f"Status: {response.status_code}")

    @task(2)
    def slow_request(self):
        """Медленный запрос — должен привести к таймауту (>3 секунд)"""
        with self.client.get(
            "/logistics/?type=slow",
            name="[CB] Slow request (timeout test)",
            catch_response=True,
        ) as response:
            if response.status_code == 503:
                try:
                    data = response.json()
                    if data.get("fallback"):
                        logger.info(
                            "CIRCUIT BREAKER OPEN — timeout triggered fallback!"
                        )
                        response.failure("CB open - timeout fallback")
                    else:
                        response.failure("Timeout/Error from upstream")
                except Exception:
                    response.failure("Timeout/Error from upstream")
            elif response.status_code == 504:
                logger.info("Gateway Timeout — as expected for slow requests")
                response.failure("Gateway timeout (expected)")
            elif response.status_code == 200:
                # Если ответ пришёл (тестовый сервер не делает реальный delay)
                response.success()
            else:
                response.failure(f"Status: {response.status_code}")

    @task(1)
    def recovery_check(self):
        """Проверка восстановления после закрытия Circuit Breaker"""
        with self.client.get(
            "/logistics/fast",
            name="[CB] Recovery check (/fast)",
            catch_response=True,
        ) as response:
            if response.status_code == 200:
                try:
                    data = response.json()
                    if data.get("fallback"):
                        logger.info("CB still open — recovery not yet")
                        response.failure("CB still open")
                    else:
                        logger.info("SERVICE RECOVERED — Circuit Breaker closed!")
                        response.success()
                except Exception:
                    response.success()
            elif response.status_code == 503:
                logger.info("CB still open — waiting for recovery...")
                response.failure("CB open - waiting for recovery")
            else:
                response.failure(f"Status: {response.status_code}")


@events.test_stop.add_listener
def on_test_stop(environment, **kwargs):
    """Итоговая статистика по Circuit Breaker"""
    stats = environment.stats
    logger.info("=" * 60)
    logger.info("CIRCUIT BREAKER TEST RESULTS")
    logger.info("=" * 60)
    for entry in stats.entries.values():
        total = entry.num_requests + entry.num_failures
        logger.info(
            f"{entry.name}: "
            f"Total={total}, "
            f"Success={entry.num_requests - entry.num_failures}, "
            f"Failed/Fallback={entry.num_failures}, "
            f"Avg Response Time={entry.avg_response_time:.0f}ms"
        )
    logger.info("=" * 60)