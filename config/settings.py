"""Central config, loaded from environment / .env (never hard-coded)."""

from __future__ import annotations

from pathlib import Path

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict

REPO_ROOT = Path(__file__).resolve().parent.parent


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=REPO_ROOT / ".env",
        env_prefix="",
        extra="ignore",
    )

    snowflake_account: str = Field(alias="SNOWFLAKE_ACCOUNT")
    snowflake_user: str = Field(alias="SNOWFLAKE_USER")
    snowflake_password: str = Field(alias="SNOWFLAKE_PASSWORD")
    snowflake_role: str = Field(default="ACCOUNTADMIN", alias="SNOWFLAKE_ROLE")
    snowflake_warehouse: str = Field(default="RB_LOAD_WH", alias="SNOWFLAKE_WAREHOUSE")
    snowflake_database: str = Field(default="REDBULL_DELIVERY", alias="SNOWFLAKE_DATABASE")

    raw_data_dir: Path = Field(alias="RAW_DATA_DIR")

    def connect_kwargs(self) -> dict[str, str]:
        return {
            "account": self.snowflake_account,
            "user": self.snowflake_user,
            "password": self.snowflake_password,
            "role": self.snowflake_role,
            "warehouse": self.snowflake_warehouse,
        }


def load_settings() -> Settings:
    return Settings()  # type: ignore[call-arg]
