import logging
import os
import random
import subprocess
import time

import undetected_chromedriver as uc

from datetime import datetime, timedelta
from dotenv import load_dotenv

from playsound import playsound

from selenium import webdriver
from selenium.webdriver.support.ui import Select, WebDriverWait
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.common.by import By
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.common.action_chains import ActionChains, ScrollOrigin

from tg_notifyer import send_message_to_telegram

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))


class FirewallException(Exception):
    """Custom exception for firewall-related issues."""
    pass


def get_logger(logger_name=None):
    logger = logging.getLogger(__name__)
    log_name = f"{logger_name}.log" if logger_name else f"{SCRIPT_DIR}/cita_catcher.log"
    logging.basicConfig(format='%(asctime)s.%(msecs)03d %(levelname)-8s %(message)s', level=logging.INFO, datefmt='%Y-%m-%d %H:%M:%S',
                    handlers=[logging.FileHandler(log_name, mode='a'), logging.StreamHandler()])
    return logger


def wait_until_next_hour_plus(seconds_offset=1):
    now = datetime.now()
    next_minute = (now + timedelta(minutes=1)).replace(second=0, microsecond=0)
    target_time = next_minute + timedelta(seconds=seconds_offset)
    sleep_time = (target_time - datetime.now()).total_seconds()
    if sleep_time > 0:
        time.sleep(sleep_time)


def verify_firewall(driver):
    text = "The requested URL was rejected. Please consult with your administrador."
    if text in driver.page_source:
        logger.warning("The requested URL was rejected. Please consult with your administrador.")
        subprocess.run(["afplay", f"{SCRIPT_DIR}/cita_fail.mp3"])
        raise FirewallException("Firewall issue detected")

def find_cita(driver):
    logger.info("Starting cita search process")

    driver.get("https://icp.administracionelectronica.gob.es/icpplus/index")

    wait = WebDriverWait(driver, 10)

    logger.info("Waiting for the 'Seleccionar provincia' element to be present")
    province_select = Select(wait.until(EC.presence_of_element_located((By.NAME, "form"))))
    province_select.select_by_visible_text("Castellón")
    logger.info("Click ACCEPT button after selecting province")
    driver.find_element(By.ID, "btnAceptar").click()
    verify_firewall(driver)


    office_select = Select(wait.until(EC.presence_of_element_located((By.NAME, "sede"))))
    office_select.select_by_visible_text("CNP COMISARIA, PLAZA TEODORO IZQUIERDO, 6, CASTELLÓN DE LA PLANA")
    logger.info("Selecting office and waiting for the next step")
    time.sleep(1)

    procedure_select = Select(wait.until(EC.presence_of_element_located((By.NAME, "tramiteGrupo[0]"))))
    procedure_select.select_by_visible_text("POLICÍA TARJETA CONFLICTO UCRANIA–ПОЛІЦІЯ -КАРТКА ДЛЯ ПЕРЕМІЩЕНИХ ОСІБ ВНАСЛІДОК КОНФЛІКТУ В УКРАЇНІ")
    logger.info("Selecting procedure and waiting for the next step")
    time.sleep(1)
    driver.find_element(By.ID, "btnAceptar").click()
    verify_firewall(driver)


    logger.info("Scrolling down to the 'Entrar' button")
    scroll_origin = ScrollOrigin.from_viewport(10, 10)
    ActionChains(driver)\
        .scroll_from_origin(scroll_origin, 0, 1200)\
        .perform()

    time.sleep(2)
    logger.info("Click ACCEPT button for user agreement")
    driver.find_element(By.ID, "btnEntrar").click()
    verify_firewall(driver)

    # Wait until the input fields are visible
    wait.until(EC.presence_of_element_located((By.NAME, "txtIdCitado")))
    wait.until(EC.presence_of_element_located((By.NAME, "txtDesCitado")))

    logger.info("Filling in the input fields with random delays")
    field = driver.find_element(By.NAME, "txtIdCitado")
    field.clear()
    for char in os.environ.get("ID_NUMBER"):
        field.send_keys(char)
        random_delay = random.uniform(0.05, 0.2)  # Random delay between 50ms and 200ms
        time.sleep(random_delay)

    surname = driver.find_element(By.NAME, "txtDesCitado")
    surname.clear()
    for char in os.environ.get("FIRST_NAME_LAST_NAME"):
        surname.send_keys(char)
        random_delay = random.uniform(0.05, 0.2)  # Random delay between 50ms and 200ms
        time.sleep(random_delay)

    time.sleep(1)
    logger.info("Click ACCEPT button after filling in the fields")
    driver.find_element(By.ID, "btnEnviar").click()
    verify_firewall(driver)

    logger.info("Waiting for the next minute starts")
    wait_until_next_hour_plus(0.5)
    time.sleep(3) # Wait 3 sec after new hour
    logger.info("Click ACCEPT button to get cita")
    driver.find_element(By.ID, "btnEnviar").click()
    verify_firewall(driver)

    text = "En este momento no hay citas disponibles."
    if text in driver.page_source:
        logger.info("NO CITAS AVAILABLE")
        playsound(os.path.join(SCRIPT_DIR, "cita_fail.mp3"))
        return
    else:
        logger.info("Cita found.")
        send_message_to_telegram()
        playsound(os.path.join(SCRIPT_DIR, "cita_found.mp3"))
        time.sleep(600)


def main():
    options = Options()
    options.add_argument("--start-maximized")
    options.add_argument("--user-agent=Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
                        "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36")
    options.add_experimental_option("excludeSwitches", ["enable-automation"])
    options.add_experimental_option("useAutomationExtension", False)
    driver = webdriver.Chrome(options=options)

    # options = uc.ChromeOptions()
    # options.add_argument("--no-sandbox")
    # options.add_argument("--disable-blink-features=AutomationControlled")
    # options.add_argument("--disable-extensions")
    # options.add_argument("--disable-gpu")
    # options.add_argument("--disable-dev-shm-usage")
    # options.add_argument("--lang=es-ES")
    # options.add_argument("--incognito")
    # options.add_argument("--start-maximized")
    # options.add_argument("--user-agent=Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36")
    # options.add_argument("--lang=es-ES,es;q=0.9")
    # driver = uc.Chrome(options=options)

    driver.execute_cdp_cmd(
        'Page.addScriptToEvaluateOnNewDocument',
        {
            'source': '''
                Object.defineProperty(navigator, 'webdriver', {
                    get: () => false
                })
            '''
        }
    )

    try:
        find_cita(driver)
    except FirewallException as e:
        logger.error(f"Firewall issue detected: {e}")
    except Exception as e:
        logger.error(f"An unexpected error occurred: {e}")


if __name__ == "__main__":
    load_dotenv()
    logger = get_logger()
    logger.info("---------------------------------")
    logger.info("")
    logger.info("Starting cita catcher script")
    main()
    logger.info("Cita catcher script finished")


