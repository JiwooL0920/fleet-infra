"""YAML parsing helpers for docgen."""

from __future__ import annotations

from typing import Any

import yaml


def load_yaml_documents(text: str) -> list[dict[str, Any]]:
    """Parse one or more YAML documents into mapping documents.

    Empty documents are ignored. Non-mapping documents are also ignored because
    docgen callers only operate on resource mappings.
    """
    documents: list[dict[str, Any]] = []
    for doc in yaml.safe_load_all(text):
        if isinstance(doc, dict):
            documents.append(doc)
    return documents


def split_yaml_documents(text: str) -> list[str]:
    """Split YAML input into document source strings using --- separators."""
    docs: list[str] = []
    current: list[str] = []
    for line in text.splitlines(keepends=True):
        if line.strip() == "---":
            if "".join(current).strip():
                docs.append("".join(current))
            current = []
            continue
        current.append(line)
    if "".join(current).strip():
        docs.append("".join(current))
    return docs


def load_yaml_documents_with_source(text: str) -> list[tuple[str, dict[str, Any]]]:
    """Parse YAML docs and preserve each doc's original source text."""
    docs_with_source: list[tuple[str, dict[str, Any]]] = []
    for source in split_yaml_documents(text):
        for loaded in yaml.safe_load_all(source):
            if isinstance(loaded, dict):
                docs_with_source.append((source, loaded))
    return docs_with_source


def get_nested(mapping: dict[str, Any], *keys: str, default: Any = None) -> Any:
    """Safely fetch nested keys from a mapping, returning default when absent."""
    current: Any = mapping
    for key in keys:
        if not isinstance(current, dict):
            return default
        if key not in current:
            return default
        current = current[key]
    return current
