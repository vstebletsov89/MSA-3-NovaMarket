from locust import HttpUser, task, between

class APIUser(HttpUser):
    wait_time = between(1, 2)

    def check_response(self, response):
        if response.status_code == 200:
            response.success()
        elif response.status_code == 503 and "Circuit breaker is open" in response.text:
            print(f"Circuit Breaker is open: {response.text}")
            response.failure(f"CB OPEN (Fallback): {response.text}")
        else:
            response.failure(f"ERROR {response.status_code}: {response.text}")

    @task(4)
    def test_fast(self):
        with self.client.get("/logistics/?type=fast", name="[FAST]", catch_response=True) as r:
            self.check_response(r)

    @task(1)
    def test_error(self):
        with self.client.get("/logistics/?type=error", name="[ERROR]", catch_response=True) as r:
            self.check_response(r)

    @task(1)
    def test_slow(self):
        with self.client.get("/logistics/?type=slow", name="[SLOW]", catch_response=True) as r:
            self.check_response(r)