# Copyright © 2022 Amazon Web Services, Inc. or its affiliates. All Rights Reserved. This AWS Content is provided subject to the terms of the AWS Customer Agreement available at http://aws.amazon.com/agreement or other written agreement between Customer and either Amazon Web Services, Inc. or Amazon Web Services EMEA SARL or both."

FROM python:3.7-alpine

WORKDIR /opt/app

COPY . .

RUN pip install --no-cache-dir -r requirements.txt

EXPOSE 8080

CMD ["python3", "-m", "flask", "run", "--host=0.0.0.0", "--port=8080"]