from locust import HttpUser, task, constant, between

class APIUser(HttpUser):
    wait_time = between(0.01, 0.05)

    @task(5)
    def test_web(self):
        self.client.get("/api/web/", name="[WEB] Limit 50 r/s")

    @task(3)
    def test_mobile(self):
        self.client.get("/api/mobile/", name="[MOBILE] Limit 30 r/s")