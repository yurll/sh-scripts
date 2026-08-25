#!/usr/bin/env bash

alias aws_whoami="aws sts get-caller-identity --query 'Account' --output text"
