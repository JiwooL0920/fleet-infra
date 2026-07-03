from __future__ import annotations

import yaml

from lib.parse import get_nested, load_yaml_documents, load_yaml_documents_with_source


def test_load_yaml_documents_single_doc() -> None:
    text = """
kind: HelmRelease
metadata:
  name: traefik
"""
    docs = load_yaml_documents(text)
    assert len(docs) == 1
    assert get_nested(docs[0], "kind") == "HelmRelease"
    assert get_nested(docs[0], "metadata", "name") == "traefik"


def test_load_yaml_documents_multi_doc() -> None:
    text = """
kind: HelmRepository
metadata:
  name: bitnami
---
kind: HelmRelease
metadata:
  name: redis
"""
    docs = load_yaml_documents(text)
    assert [get_nested(d, "kind") for d in docs] == ["HelmRepository", "HelmRelease"]


def test_load_yaml_documents_anchors_and_refs() -> None:
    text = """
defaults: &defaults
  namespace: monitoring
resource:
  <<: *defaults
  name: grafana
"""
    docs = load_yaml_documents(text)
    doc = docs[0]
    assert get_nested(doc, "resource", "namespace") == "monitoring"
    assert get_nested(doc, "resource", "name") == "grafana"


def test_load_yaml_documents_block_scalars() -> None:
    text = """
intro: |
  line one
  line two
purpose: >
  wrapped
  text
"""
    doc = load_yaml_documents(text)[0]
    assert get_nested(doc, "intro") == "line one\nline two\n"
    assert get_nested(doc, "purpose") == "wrapped text\n"


def test_get_nested_missing_keys_default_and_none() -> None:
    doc = {"spec": {"path": "./apps/base/n8n"}}
    assert get_nested(doc, "spec", "path") == "./apps/base/n8n"
    assert get_nested(doc, "spec", "timeout") is None
    assert get_nested(doc, "spec", "timeout", default="5m") == "5m"
    assert get_nested(doc, "metadata", "name", default="unknown") == "unknown"


def test_load_yaml_documents_malformed_yaml_raises_clearly() -> None:
    text = "kind: HelmRelease\nmetadata: [unclosed\n"
    try:
        load_yaml_documents(text)
    except yaml.YAMLError:
        return
    raise AssertionError("Expected yaml.YAMLError for malformed YAML")


def test_load_yaml_documents_with_source_preserves_doc_comments() -> None:
    text = """
kind: ConfigMap
spec:
  timeout: 5m  # keep me
"""
    docs = load_yaml_documents_with_source(text)
    assert len(docs) == 1
    source, doc = docs[0]
    assert "timeout: 5m  # keep me" in source
    assert get_nested(doc, "spec", "timeout") == "5m"
