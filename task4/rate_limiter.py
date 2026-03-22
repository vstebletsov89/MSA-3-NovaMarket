from locust import HttpUser, task, between, events
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("rate_limiter_test")


class WebAppUser(HttpUser):
    """Имитация веб-приложения — лимит 50 r/s на IP"""
    wait_time = between(0.01, 0.05)  # Агрессивная нагрузка для срабатывания лимита
    weight = 5  # Больше веб-пользователей

    @task
    def web_api_request(self):
        with self.client.get(
            "/api/web/",
            headers={"Client-Type": "web"},
            name="[WEB] /api/web/",
            catch_response=True,
        ) as response:
            if response.status_code == 200:
                response.success()
            elif response.status_code == 429:
                logger.info("WEB Rate Limit triggered! HTTP 429")
                response.failure("Rate limited (429)")
            elif response.status_code == 503:
                logger.info("WEB Rate Limit triggered! HTTP 503")
                response.failure("Rate limited (503)")
            else:
                response.failure(f"Unexpected status: {response.status_code}")


class MobileAppUser(HttpUser):
    """Имитация мобильного приложения — лимит 30 r/s на IP"""
    wait_time = between(0.01, 0.05)  # Агрессивная нагрузка для срабатывания лимита
    weight = 3  # Меньше мобильных пользователей

    @task
    def mobile_api_request(self):
        with self.client.get(
            "/api/mobile/",
            headers={"Client-Type": "mobile"},
            name="[MOBILE] /api/mobile/",
            catch_response=True,
        ) as response:
            if response.status_code == 200:
                response.success()
            elif response.status_code == 429:
                logger.info("MOBILE Rate Limit triggered! HTTP 429")
                response.failure("Rate limited (429)")
            elif response.status_code == 503:
                logger.info("MOBILE Rate Limit triggered! HTTP 503")
                response.failure("Rate limited (503)")
            else:
                response.failure(f"Unexpected status: {response.status_code}")


@events.test_stop.add_listener
def on_test_stop(environment, **kwargs):
    """Выводим итоговую статистику по срабатыванию Rate Limiter"""
    stats = environment.stats
    logger.info("=" * 60)
    logger.info("RATE LIMITER TEST RESULTS")
    logger.info("=" * 60)
    for entry in stats.entries.values():
        total = entry.num_requests + entry.num_failures
        logger.info(
            f"{entry.name}: "
            f"Total={total}, "
            f"Success={entry.num_requests - entry.num_failures}, "
            f"Rate Limited={entry.num_failures}"
        )
    logger.info("=" * 60)