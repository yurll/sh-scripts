import requests
import logging

logger = logging.getLogger(__name__)


def send_message_to_telegram(token, chat_ids, message):
    if not token or not chat_ids:
        logger.warning("Telegram token or chat IDs are not set.")
        return
    for chat_id in chat_ids.split(','):
        url = f"https://api.telegram.org/bot{token}/sendMessage?chat_id={chat_id}&text={message}"
        requests.get(url)


if __name__ == "__main__":
    import os
    from dotenv import load_dotenv
    load_dotenv()
    send_message_to_telegram(os.environ.get('TG_TOKEN'), os.environ.get('CHAT_IDS'))
