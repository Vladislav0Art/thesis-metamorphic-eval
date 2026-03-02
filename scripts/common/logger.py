import logging

def configure_logging(log_filename: str, level=logging.INFO):
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(levelname)s - %(message)s',
        handlers=[
            logging.FileHandler(log_filename),
            logging.StreamHandler(),
        ]
    )
