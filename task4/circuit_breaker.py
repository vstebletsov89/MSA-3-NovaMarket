from locust import HttpUser, task, between

class CircuitBreakerUser(HttpUser):
    wait_time = between(1, 2)

    @task(4)
    def test_fast(self):
        """Нормальный запрос — ожидаем 200 OK"""
        self.client.get("/logistics/?type=fast", name="1. Normal (Fast)")

    @task(1)
    def test_error(self):
        """Запрос с ошибкой — провоцирует размыкание цепи (max_fails=5)"""
        with self.client.get("/logistics/?type=error", name="2. Error (Trigger CB)", catch_response=True) as r:
            if r.status_code == 503 and "Circuit breaker is open" in r.text:
                print(f"DEBUG: Status 503 received. Body: {r.text}")
                r.failure("CB OPEN: Fallback Active")
            elif r.status_code == 500:
                r.failure("CB CLOSED: Raw Error from Backend")

    @task(1)
    def test_slow(self):
        """Медленный запрос — должен отсекаться по proxy_read_timeout 3s"""
        with self.client.get("/logistics/?type=slow", name="3. Slow (Timeout)", catch_response=True) as r:
            # Nginx вернет 504 (Timeout) или 503 (если CB уже открыт)
            if r.status_code in [503, 504]:
                r.failure(f"Timeout/Fallback: {r.status_code}")