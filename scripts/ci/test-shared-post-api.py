#!/usr/bin/env python3
"""Check the installed client's RPC payload through isolated PostgREST, not production."""
import base64
import hashlib
import hmac
import json
import os
import subprocess
import sys
import time

container, database = sys.argv[1:]
api_container = f"wrkt_postgrest_test_{os.getpid()}"
secret = "wrkt-isolated-contract-test-secret-only-2026"


def run(*args, **kwargs):
    return subprocess.run(args, check=True, capture_output=True, text=True, **kwargs).stdout.strip()


def sql(statement):
    return run("docker", "exec", "-i", container, "psql", "-X", "-U", "postgres", "-d", database,
               "-At", "-v", "ON_ERROR_STOP=1", input=statement)


def token(user):
    encode = lambda value: base64.urlsafe_b64encode(value).rstrip(b"=")
    header = encode(json.dumps({"alg": "HS256", "typ": "JWT"}).encode())
    claims = encode(json.dumps({"role": "authenticated", "sub": user, "exp": int(time.time()) + 300}).encode())
    message = header + b"." + claims
    return (message + b"." + encode(hmac.new(secret.encode(), message, hashlib.sha256).digest())).decode()


def request(body, user=None):
    args = ["docker", "exec", container, "curl", "-sS", "--max-time", "5", "-w", "\n%{http_code}",
            "-H", "Content-Type: application/json"]
    if user:
        args.extend(["-H", "Authorization: Bearer " + token(user)])
    args.extend(["--data-binary", json.dumps(body), "http://127.0.0.1:3000/rpc/create_shared_post"])
    response, status = run(*args).rsplit("\n", 1)
    return int(status), response


try:
    run("docker", "run", "--detach", "--name", api_container, "--network", f"container:{container}",
        "-e", f"PGRST_DB_URI=postgresql://postgres:wrkt-local-tests-only@127.0.0.1:5432/{database}",
        "-e", "PGRST_DB_ANON_ROLE=anon", "-e", "PGRST_DB_SCHEMAS=public",
        "-e", f"PGRST_JWT_SECRET={secret}", "public.ecr.aws/supabase/postgrest:v14.3")
    for attempt in range(30):
        try:
            run("docker", "exec", container, "curl", "-fsS", "--max-time", "1", "http://127.0.0.1:3000/")
            break
        except subprocess.CalledProcessError:
            if attempt == 29:
                raise RuntimeError("Isolated PostgREST did not become ready")
            time.sleep(0.1)

    author = "11111111-1111-1111-1111-111111111111"
    partner = "22222222-2222-2222-2222-222222222222"
    outsider = "33333333-3333-3333-3333-333333333333"
    sql(f"insert into public.friendships(user_id,friend_id,status) values ('{author}','{partner}','accepted');")
    payload = {"p_visibility": "friends", "p_images": [], "p_workout_data": {"id": "fixture-run"}, "p_partner_user_id": partner}
    cases = [
        ("anonymous denied", payload, None, 401),
        ("nonfriend denied", payload, outsider, 403),
        ("required values validated", {}, author, 400),
        ("installed client omitted arguments", payload, author, 200),
        ("new client explicit nulls", {**payload, "p_caption": None, "p_workout_data_list": None,
                                      "p_partner_vr_stats": None, "p_run_id": None}, author, 200),
    ]
    for name, body, user, expected in cases:
        status, response = request(body, user)
        if status != expected:
            raise AssertionError(f"{name}: expected {expected}, received {status}: {response}")
        print(f"PASS: {name} (HTTP {status})")
    assert sql("select count(*) from public.workout_posts;") == "2"
    assert sql("select count(*) from public.post_participants;") == "2"
    assert sql("select count(*) from public.notifications;") == "2"
finally:
    subprocess.run(["docker", "rm", "--force", api_container], capture_output=True, text=True)
