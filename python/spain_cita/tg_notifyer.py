import os
import requests

from dotenv import load_dotenv

def send_message_to_telegram():
    load_dotenv()
    token = os.environ.get('TG_TOKEN')
    chat_id = os.environ.get('CHAT_ID')
    message = "Cita found! Hurry up!"
    url = f"https://api.telegram.org/bot{token}/sendMessage?chat_id={chat_id}&text={message}"
    requests.get(url)

if __name__ == "__main__":
    send_message_to_telegram()