#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d /tmp/viewfinder-home-tests.XXXXXX)
# One compilation unit lets the private cache implementation be tested through its VM.
# Time-context code is read directly from production; no copied algorithm lives in the fixtures.
{
    cat Viewfinder/Models/HomeRecommendationsViewModel.swift
    cat Viewfinder/Services/RecommendationLocationReader.swift
    awk '/^struct RecommendationTimeContext/{copy=1} /^\/\/\/ Pure/{copy=0} copy' Viewfinder/Services/LocalSeedDataService.swift
    cat Tools/HomeContextRegression.swift
} | swiftc -parse-as-library - -o "$test_dir/regression"
"$test_dir/regression"
