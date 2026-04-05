#!/usr/bin/env python3

import json
import os
import sys
from collections import defaultdict


PROVIDER_SPECS = {
    "openai": {
        "api_key_env": "OPENAI_API_KEY",
        "base_url": "https://api.openai.com/v1",
    },
    "openrouter": {
        "api_key_env": "OPENROUTER_API_KEY",
        "base_url": "https://openrouter.ai/api/v1",
    },
    "deepseek": {
        "api_key_env": "DEEPSEEK_API_KEY",
        "base_url": "https://api.deepseek.com/v1",
    },
    "minimax": {
        "api_key_env": "MINIMAX_API_KEY",
        "base_url": "https://api.minimaxi.com/v1",
    },
    "kimi": {
        "api_key_env": "KIMI_API_KEY",
        "base_url": "https://api.moonshot.cn/v1",
    },
    "custom": {
        "api_key_env": "CUSTOM_OPENAI_API_KEY",
        "base_url_env": "CUSTOM_OPENAI_BASE_URL",
    },
}


def read_json(path: str) -> dict:
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def write_json(path: str, data: dict) -> None:
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)
        f.write("\n")


def env_model(name: str, default: str = "") -> str:
    return (os.environ.get(name) or default).strip()


def parse_model_ref(model_ref: str) -> tuple[str, str]:
    if "/" not in model_ref:
        raise ValueError(
            f"Model '{model_ref}' must use provider/model format, for example openai/gpt-4.1"
        )
    provider, model_id = model_ref.split("/", 1)
    provider = provider.strip()
    model_id = model_id.strip()
    if not provider or not model_id:
        raise ValueError(
            f"Model '{model_ref}' must use provider/model format, for example openai/gpt-4.1"
        )
    return provider, model_id


def ensure_provider(provider: str) -> dict:
    if provider not in PROVIDER_SPECS:
        supported = ", ".join(sorted(PROVIDER_SPECS))
        raise ValueError(f"Unsupported provider '{provider}'. Supported providers: {supported}")

    spec = PROVIDER_SPECS[provider]
    api_key = (os.environ.get(spec["api_key_env"]) or "").strip()
    if not api_key:
        raise ValueError(
            f"Provider '{provider}' requires env var {spec['api_key_env']} to be set"
        )

    base_url = spec.get("base_url")
    if not base_url:
        base_url = (os.environ.get(spec.get("base_url_env", "")) or "").strip()
        if not base_url:
            raise ValueError(
                f"Provider '{provider}' requires env var {spec['base_url_env']} to be set"
            )

    return {
        "baseUrl": base_url,
        "apiKey": "${" + spec["api_key_env"] + "}",
        "api": "openai-completions",
        "authHeader": True,
        "models": [],
    }


def model_entry(model_id: str) -> dict:
    return {
        "id": model_id,
        "name": model_id,
        "reasoning": True,
        "input": ["text"],
        "contextWindow": 200000,
        "maxTokens": 100000,
    }


def main() -> int:
    if len(sys.argv) != 2:
        print("Usage: configure-openclaw-models.py <openclaw.json>", file=sys.stderr)
        return 1

    path = sys.argv[1]
    config = read_json(path)

    primary_model = env_model("CLAWOSS_PRIMARY_MODEL", "minimax/MiniMax-M2.7")
    fallback_model = env_model("CLAWOSS_FALLBACK_MODEL", "")
    subagent_model = env_model("CLAWOSS_SUBAGENT_MODEL", primary_model)
    heartbeat_model = env_model("CLAWOSS_HEARTBEAT_MODEL", primary_model)
    agent_model = env_model("CLAWOSS_AGENT_MODEL", primary_model)

    model_refs = [primary_model, subagent_model, heartbeat_model, agent_model]
    if fallback_model:
        model_refs.append(fallback_model)

    provider_models: dict[str, set[str]] = defaultdict(set)
    for model_ref in model_refs:
        provider, model_id = parse_model_ref(model_ref)
        provider_models[provider].add(model_id)

    providers = {}
    for provider, model_ids in provider_models.items():
        provider_config = ensure_provider(provider)
        provider_config["models"] = [model_entry(model_id) for model_id in sorted(model_ids)]
        providers[provider] = provider_config

    config.setdefault("agents", {}).setdefault("defaults", {})
    config["agents"]["defaults"].setdefault("model", {})
    config["agents"]["defaults"]["model"]["primary"] = primary_model
    config["agents"]["defaults"]["model"]["fallbacks"] = [fallback_model] if fallback_model else []

    config["agents"]["defaults"].setdefault("subagents", {})
    config["agents"]["defaults"]["subagents"]["model"] = subagent_model

    for agent in config["agents"].get("list", []):
        agent["model"] = agent_model
        heartbeat = agent.get("heartbeat")
        if isinstance(heartbeat, dict):
            heartbeat["model"] = heartbeat_model

    config.setdefault("models", {})
    config["models"]["mode"] = "merge"
    config["models"]["providers"] = providers

    config.setdefault("env", {})
    config["env"]["CLAWOSS_PRIMARY_MODEL"] = primary_model
    if fallback_model:
        config["env"]["CLAWOSS_FALLBACK_MODEL"] = fallback_model
    else:
        config["env"].pop("CLAWOSS_FALLBACK_MODEL", None)
    config["env"]["CLAWOSS_SUBAGENT_MODEL"] = subagent_model
    config["env"]["CLAWOSS_HEARTBEAT_MODEL"] = heartbeat_model
    config["env"]["CLAWOSS_AGENT_MODEL"] = agent_model
    config["env"]["CLAWOSS_DEFAULT_MODEL"] = primary_model

    write_json(path, config)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
