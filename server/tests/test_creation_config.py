"""키 이름 호환성과 실행 위치에 독립적인 서버 설정."""

from pathlib import Path

from app.config import Settings


def test_openrouter_key_alias_from_environment(monkeypatch):
    monkeypatch.delenv("OPENROUTER_API_KEY", raising=False)
    monkeypatch.setenv("OPENROUTER_KEY", "fake-test-key")
    settings = Settings(_env_file=None)
    assert settings.openrouter_api_key is not None
    assert settings.openrouter_api_key.get_secret_value() == "fake-test-key"


def test_env_path_is_absolute_and_secret_field_hides_value():
    assert Path(Settings.model_config["env_file"]).is_absolute()
    settings = Settings(_env_file=None, openrouter_api_key="fake-test-key")
    assert "fake-test-key" not in repr(settings)
