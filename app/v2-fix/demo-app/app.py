# Copyright © 2022 Amazon Web Services, Inc. or its affiliates. All Rights Reserved. This AWS Content is provided subject to the terms of the AWS Customer Agreement available at http://aws.amazon.com/agreement or other written agreement between Customer and either Amazon Web Services, Inc. or Amazon Web Services EMEA SARL or both."

import os
from random import random

from flask import Flask, jsonify
from flask_api import status

from config import __version__

app = Flask(__name__)

app.config["DEBUG"] = os.environ.get("DEBUG")

@app.route("/")
def home():
    return "Hello AWS! I am healthy!"


@app.route("/version")
def version():
    return f"App Version: {__version__}"


@app.route("/sample_api")
def sample_api():
    if random() <= 1:
        return jsonify(status="healthy", version=__version__)
    else:
        return (
            jsonify(status="unhealthy", version=__version__),
            status.HTTP_500_INTERNAL_SERVER_ERROR,
        )
