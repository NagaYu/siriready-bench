#!/usr/bin/env python3
"""Deterministic generator for the SiriReady Bench utterance dataset (public edition: v1.2 only).

Standard library only. Every person, event, message and title below is invented for this
benchmark; nothing is taken from real people or real apps. Output:

  v1.2/cases_dev.jsonl    messages app (dev split, 624 cases)
  v1.2/cases_eval.jsonl   calendar app (eval split, 648 cases; app-disjoint from dev)
  v1.2/entities/<app_id>.json   synthetic entity catalogs referenced by the cases

The dataset is built in stages with fixed seeds (base templates, paraphrase blocks, data-gap
cases). Paraphrase families A/B occur only in dev and C/D only in eval (generator-holdout).
Earlier dataset versions are not part of the public repository (see dataset/BENCH_CARD.md).

Run:  python3.12 dataset/generate.py [--out DIR]
"""
from __future__ import annotations

import argparse
import json
import pathlib
import random

SEED = 27
DATASET_VERSION = "v0"
SPLIT_OF_APP = {"messages": "dev", "calendar": "eval"}  # app-disjoint splits
PER_LOCALE = 100


# ---------------------------------------------------------------------------
# Synthetic entity catalogs
# ---------------------------------------------------------------------------

def form(text, reading=None):
    f = {"text": text}
    if reading:
        f["reading"] = reading
    return f


def contact(cid, name, aliases=(), reading=None, qualifiers=(), locale="en-US"):
    """`aliases` holds plain strings (EN) or (text, reading) pairs (JA)."""
    forms = [form(name, reading)] + [form(a) if isinstance(a, str) else form(*a) for a in aliases]
    return {"id": cid, "type": "ContactEntity", "locale": locale, "forms": forms,
            "qualifiers": list(qualifiers), "related": {}, "attrs": {}}


EN_CONTACTS = [
    contact("c_alex", "Alex Rivera", ["Alex"]),
    contact("c_anjali", "Anjali Raghunathan", ["Anjali"]),
    contact("c_shawn", "Shawn Patel", ["Shawn"]),
    contact("c_kate", "Katherine Osei", ["Kate", "Katie"]),
    contact("c_marcus", "Marcus Lindqvist", ["Marcus"]),
    contact("c_dani", "Daniela Fischer", ["Dani"]),
    contact("c_omar", "Omar Haddad", ["Omar"]),
    contact("c_rae", "Rae Thompson", ["Rae"]),
    contact("c_samlee_work", "Sam Lee", qualifiers=["work", "office"]),
    contact("c_samlee_gym", "Sam Lee", qualifiers=["gym"]),
    contact("c_jon_park", "Jon Park", qualifiers=["design"]),
    contact("c_john_parke", "John Parke", qualifiers=["finance"]),
]

JA_CONTACTS = [
    contact("j_takase", "高瀬 美月", [("美月", "みづき")], "たかせ みづき", locale="ja-JP"),
    contact("j_mori", "森 瑞希", [("瑞希", "みづき")], "もり みづき", locale="ja-JP"),
    contact("j_sato", "佐藤 光", [("光", "ひかる")], "さとう ひかる", locale="ja-JP"),
    contact("j_saito", "齊藤 健", [("斉藤 健", "さいとう けん"), ("斎藤 健", "さいとう けん")], "さいとう けん", locale="ja-JP"),
    contact("j_onodera", "小野寺 葵", reading="おのでら あおい", locale="ja-JP"),
    contact("j_ishikawa", "石川 大翔", [("ヒロト", "ひろと")], "いしかわ ひろと", locale="ja-JP"),
    contact("j_fujii", "藤井 蓮", reading="ふじい れん", locale="ja-JP"),
    contact("j_nakamura_work", "中村 結衣", reading="なかむら ゆい", qualifiers=["仕事", "会社"], locale="ja-JP"),
    contact("j_nakamura_uni", "中村 結衣", reading="なかむら ゆい", qualifiers=["大学", "サークル"], locale="ja-JP"),
    contact("j_kato_tennis", "加藤 涼", reading="かとう りょう", qualifiers=["テニス"], locale="ja-JP"),
    contact("j_kato_acct", "加藤 遼", reading="かとう りょう", qualifiers=["経理"], locale="ja-JP"),
]

MESSAGE_SNIPPETS = {
    "en-US": [("c_alex", "Running late, sorry"), ("c_anjali", "Slides attached for Friday"),
              ("c_omar", "Are we still on for lunch"), ("c_kate", "Parking is on level two"),
              ("c_marcus", "Package arrived at reception"), ("c_dani", "Thanks for the notes")],
    "ja-JP": [("j_sato", "少し遅れます"), ("j_saito", "金曜の資料を送ります"),
              ("j_onodera", "ランチまだ行ける？"), ("j_ishikawa", "駐車場は2階です"),
              ("j_fujii", "荷物が受付に届いてます"), ("j_takase", "メモありがとう")],
}


def event(eid, title, weekday, date, time, aliases=(), reading=None, qualifiers=(), calendar="cal_work", locale="en-US"):
    forms = [form(title, reading)] + [form(*a) if isinstance(a, tuple) else form(a) for a in aliases]
    return {"id": eid, "type": "EventEntity", "locale": locale, "forms": forms,
            "qualifiers": list(qualifiers), "related": {"calendar": calendar},
            "attrs": {"weekday": weekday, "date": date, "time": time}}


EN_EVENTS = [
    event("ev_sync_mon", "Team Sync", "Monday", "2026-11-02", "10:00", qualifiers=["monday", "mon"]),
    event("ev_sync_thu", "Team Sync", "Thursday", "2026-11-05", "10:00", qualifiers=["thursday", "thu"]),
    event("ev_design_review", "Design Review", "Tuesday", "2026-11-03", "14:00", ["Design Crit"], qualifiers=["tuesday"]),
    event("ev_peer_review", "Peer Review", "Wednesday", "2026-11-04", "11:00", qualifiers=["wednesday"]),
    event("ev_brake", "Brake Inspection", "Saturday", "2026-11-07", "09:30", qualifiers=["saturday"], calendar="cal_personal"),
    event("ev_qbr", "Quarterly Business Review", "Friday", "2026-11-06", "15:00", ["QBR"], qualifiers=["friday"]),
    event("ev_standup", "Daily Standup", "Monday", "2026-11-02", "09:00", ["Standup", "Stand-up"]),
    event("ev_demo", "Product Demo", "Wednesday", "2026-11-04", "16:00", qualifiers=["wednesday"]),
    event("ev_onboarding", "Onboarding Session", "Tuesday", "2026-11-03", "10:30", ["Onboarding"], qualifiers=["tuesday"]),
    event("ev_budget", "Budget Planning", "Thursday", "2026-11-05", "13:00", qualifiers=["thursday"]),
    event("ev_jon_bday", "Jon's Birthday Dinner", "Friday", "2026-11-06", "19:00", qualifiers=["friday"], calendar="cal_personal"),
    event("ev_john_bday", "John's Birthday Dinner", "Saturday", "2026-11-07", "19:00", qualifiers=["saturday"], calendar="cal_personal"),
]

JA_EVENTS = [
    event("jev_teirei_mon", "チーム定例", "月曜", "2026-11-02", "10:00", reading="ちーむていれい", qualifiers=["月曜"], locale="ja-JP"),
    event("jev_teirei_thu", "チーム定例", "木曜", "2026-11-05", "10:00", reading="ちーむていれい", qualifiers=["木曜"], locale="ja-JP"),
    event("jev_design", "デザインレビュー", "火曜", "2026-11-03", "14:00", [("デザレビ", "でざれび")], "でざいんれびゅー", ["火曜"], locale="ja-JP"),
    event("jev_kouen_fri", "講演", "金曜", "2026-11-06", "18:00", reading="こうえん", qualifiers=["金曜"], locale="ja-JP"),
    event("jev_kouen_sat", "公演", "土曜", "2026-11-07", "18:00", reading="こうえん", qualifiers=["土曜"], calendar="cal_personal", locale="ja-JP"),
    event("jev_tanaoroshi", "在庫棚卸", "水曜", "2026-11-04", "09:00", reading="ざいこたなおろし", qualifiers=["水曜"], locale="ja-JP"),
    event("jev_setsumeikai", "製品説明会", "水曜", "2026-11-04", "15:00", reading="せいひんせつめいかい", qualifiers=["水曜"], locale="ja-JP"),
    event("jev_zensha", "全社ミーティング", "金曜", "2026-11-06", "16:00", [("全社MTG", "ぜんしゃみーてぃんぐ")], "ぜんしゃみーてぃんぐ", ["金曜"], locale="ja-JP"),
    event("jev_torihiki", "取引先打ち合わせ", "火曜", "2026-11-03", "11:00",
          [("取引先打合せ", "とりひきさきうちあわせ"), ("取引先打ち合せ", "とりひきさきうちあわせ")], "とりひきさきうちあわせ", ["火曜"], locale="ja-JP"),
    event("jev_yosan", "予算会議", "木曜", "2026-11-05", "13:00", reading="よさんかいぎ", qualifiers=["木曜"], locale="ja-JP"),
    event("jev_kenshu", "新人研修", "月曜", "2026-11-02", "13:00", [("研修", "けんしゅう")], "しんじんけんしゅう", ["月曜"], locale="ja-JP"),
    event("jev_kangeikai", "歓迎会", "金曜", "2026-11-06", "19:00", reading="かんげいかい", qualifiers=["金曜"], locale="ja-JP"),
]

CALENDARS = [
    {"id": "cal_work", "type": "CalendarEntity", "locale": "en-US", "forms": [form("Work"), form("仕事", "しごと")],
     "qualifiers": [], "related": {}, "attrs": {}},
    {"id": "cal_personal", "type": "CalendarEntity", "locale": "en-US", "forms": [form("Personal"), form("プライベート", "ぷらいべーと")],
     "qualifiers": [], "related": {}, "attrs": {}},
]

APP_INTENTS = {
    "messages": ["SendMessageIntent", "DraftMessageIntent", "SetMessageReadStatusIntent", "OpenConversationIntent"],
    "calendar": ["CreateEventIntent", "UpdateEventIntent", "DeleteEventIntent", "OpenEventIntent", "ShareEventIntent"],
}


def conversation_for(c):
    return {"id": "conv_" + c["id"], "type": "ConversationEntity", "locale": c["locale"],
            "forms": [dict(f) for f in c["forms"]], "qualifiers": list(c["qualifiers"]),
            "related": {"participant": c["id"]}, "attrs": {}}


def build_catalogs():
    contacts = EN_CONTACTS + JA_CONTACTS
    conversations = [conversation_for(c) for c in contacts]
    messages = []
    for locale, items in MESSAGE_SNIPPETS.items():
        for n, (sender, text) in enumerate(items, 1):
            messages.append({"id": f"msg_{locale[:2]}_{n:02d}", "type": "MessageEntity", "locale": locale,
                             "forms": [form(text)], "qualifiers": [], "related": {"sender": sender}, "attrs": {}})
    return {
        "messages": {"app_id": "messages", "domain": "messages", "synthetic": True, "dataset_version": DATASET_VERSION,
                     "license": "Original synthetic data created for SiriReady Bench (see BENCH_CARD.md).",
                     "intents": APP_INTENTS["messages"], "entities": contacts + conversations + messages},
        "calendar": {"app_id": "calendar", "domain": "calendar", "synthetic": True, "dataset_version": DATASET_VERSION,
                     "license": "Original synthetic data created for SiriReady Bench (see BENCH_CARD.md).",
                     "intents": APP_INTENTS["calendar"], "entities": EN_EVENTS + JA_EVENTS + CALENDARS},
    }


# ---------------------------------------------------------------------------
# Vocabulary
# ---------------------------------------------------------------------------

BODIES = {
    "en-US": ["I'm running ten minutes late", "see you at the station", "can you bring the charger",
              "the slides are ready", "lunch is on me today", "call me when you land",
              "happy birthday", "thanks for yesterday"],
    "ja-JP": ["10分遅れます", "駅で待ってるね", "充電器持ってきて", "資料できたよ",
              "今日のランチはおごるね", "着いたら電話して", "誕生日おめでとう", "昨日はありがとう"],
}
TIMES = {"en-US": ["9am", "10:30am", "1pm", "3pm", "4:30pm", "5pm"],
         "ja-JP": ["9時", "10時半", "13時", "15時", "16時半", "17時"]}
DAYS = {"en-US": ["tomorrow", "Friday", "next Monday", "Wednesday"],
        "ja-JP": ["明日", "金曜", "来週の月曜", "水曜"]}
NEW_TITLES = {"en-US": ["Dentist appointment", "Yoga class", "Car service", "Parent-teacher meeting",
                        "Coffee with the design team", "Budget check"],
              "ja-JP": ["歯医者の予約", "ヨガ教室", "車検", "保護者面談", "予算確認"]}
INVITEES = {"en-US": ["Lena", "Tomas", "Ines", "Kenji"], "ja-JP": ["山口さん", "田村さん", "吉田さん"]}

# Spoken-alike spellings an ASR front end might output. Generator-side only: the catalogs
# never contain these strings, so the index cannot match them verbatim.
ASR_VARIANTS = {
    "Shawn Patel": "Sean Patel", "Rae Thompson": "Ray Thompson",
    "Katherine Osei": "Catherine Osei", "Marcus Lindqvist": "Markus Lindqvist",
    "Peer Review": "Pier Review", "Brake Inspection": "Break Inspection",
    "Onboarding Session": "Onboarding Cession", "Design Review": "Design Revue",
    "佐藤光": "佐藤輝", "高瀬美月": "鷹瀬美月", "在庫棚卸": "在庫店卸", "製品説明会": "製品説明回",
}

EN_ORDINALS = [("first", 0), ("second", 1), ("third", 2), ("last", 2)]
JA_ORDINALS = [("一番上", 0), ("2番目", 1), ("3番目", 2), ("最後", 2)]


def by_id(entities):
    return {e["id"]: e for e in entities}


def spoken(entity, locale, form_index=0):
    """The way a user would say a form: Japanese names without the inner space."""
    text = entity["forms"][form_index]["text"]
    return text.replace(" ", "") if locale == "ja-JP" else text


def en_typo(name):
    tokens = name.split(" ")
    i = max(range(len(tokens)), key=lambda k: len(tokens[k]))
    t = tokens[i]
    for a in (1, 2, 3):
        if a + 1 < len(t) and t[a] != t[a + 1]:
            tokens[i] = t[:a] + t[a + 1] + t[a] + t[a + 2:]
            return " ".join(tokens)
    raise ValueError(name)


def ja_typo(utterance):
    # IME-style slip that leaves names and action words intact.
    if "を" in utterance:
        return utterance.replace("を", "お", 1)
    return utterance + "て"


# ---------------------------------------------------------------------------
# Case assembly
# ---------------------------------------------------------------------------

class Builder:
    def __init__(self, app, locale, rnd, seen=None, family=None, lineage="v1-para"):
        self.app, self.locale, self.rnd = app, locale, rnd
        self.cases = []
        self.seen = set() if seen is None else seen
        # Paraphrase family applied to every utterance of this block (v1 generator-holdout).
        self.family = family
        self.lineage = lineage

    def body(self):
        return self.rnd.choice(BODIES[self.locale])

    def time(self):
        return self.rnd.choice(TIMES[self.locale])

    def day(self):
        return self.rnd.choice(DAYS[self.locale])

    def invitee(self):
        return self.rnd.choice(INVITEES[self.locale])

    def add(self, make, *, tag, noise="none", adversarial=False, difficulty="easy", mention=None):
        """`make()` returns (utterance, expected, state); re-rolled until (utterance, state) is unique.

        `mention` is the surface string that names the target entity (None for on-screen,
        previous-turn and create requests). It is kept out of v0 files and written in v1."""
        for _ in range(50):
            utterance, expected, state = make()
            if self.family:
                utterance = paraphrase(self.family, self.locale, utterance)
            state = {"screen": state.get("screen"), "visible_entities": state.get("visible_entities", []),
                     "prior_turn": state.get("prior_turn")}
            key = (utterance, json.dumps(state, sort_keys=True, ensure_ascii=False))
            if key in self.seen:
                continue
            self.seen.add(key)
            exp = {"intent": expected["intent"], "entity_id": expected.get("entity_id"),
                   "params": expected.get("params", {}), "resolution": expected.get("resolution", "execute"),
                   "candidates": expected.get("candidates", [])}
            self.cases.append({
                "case_id": "", "split": SPLIT_OF_APP[self.app], "app_id": self.app, "domain": self.app,
                "locale": self.locale, "utterance": utterance, "noise": noise, "state": state,
                "expected": exp, "adversarial": adversarial, "difficulty": difficulty, "tags": [tag],
                "_mention": mention, "_generator": f"{self.lineage}-{self.family}" if self.family else "v0-template"})
            return
        raise RuntimeError(f"could not generate a unique case for {tag}")


def rotate(pool, i):
    return pool[i % len(pool)]


def ex(intent, entity_id=None, params=None, resolution="execute", candidates=()):
    return {"intent": intent, "entity_id": entity_id, "params": params or {}, "resolution": resolution,
            "candidates": list(candidates)}


# ----------------------------- messages ------------------------------------

MSG_TEMPLATES = {
    "en-US": {
        "send": ["Send {n} a message saying {b}", "Text {n} saying {b}", "Message {n}: {b}", "Tell {n}: {b}"],
        "draft": ["Draft a message to {n} saying {b}", "Write a draft to {n}: {b}",
                  "Start a message to {n} saying {b} but don't send it"],
        "open": ["Open my conversation with {n}", "Show my chat with {n}"],
    },
    "ja-JP": {
        "send": ["{n}に「{b}」って送って", "{n}へ「{b}」と送信して", "{n}にメッセージで「{b}」って伝えて"],
        "draft": ["{n}宛てに「{b}」の下書きを作って", "{n}への「{b}」ってメッセージ、まだ送らないで下書きにして"],
        "open": ["{n}とのトークを開いて", "{n}との会話を見せて"],
    },
}
MSG_NOISE = {
    "en-US": {
        "code_switch": {"send": "Send {n} a quick メッセージ saying {b}", "draft": "下書き a message to {n} saying {b}",
                        "open": "{n} との chat を open"},
        "word_order": {"send": "To {n}, send a message saying {b}", "draft": "A draft to {n}, write it saying {b}",
                       "open": "My chat with {n}, open it"},
    },
    "ja-JP": {
        "code_switch": {"send": "{n}に「{b}」ってsendして", "draft": "{n}宛てに「{b}」のdraftを作って",
                        "open": "{n}とのchatをopenして"},
        "word_order": {"send": "「{b}」って送って、{n}に", "draft": "下書きにして、{n}宛ての「{b}」",
                       "open": "開いて、{n}とのトーク"},
    },
}
MSG_INTENT = {"send": "SendMessageIntent", "draft": "DraftMessageIntent", "open": "OpenConversationIntent"}


def msg_target(action, contact_id):
    if contact_id is None:
        return None
    return ("conv_" + contact_id) if action == "open" else contact_id


def messages_cases(locale, rnd, catalog, pool=None, b=None):
    pool = pool or MESSAGE_POOLS[("v0", locale)]
    b = b or Builder("messages", locale, rnd)
    ents = by_id(catalog["entities"])
    T = MSG_TEMPLATES[locale]
    en = locale == "en-US"
    basic = pool["basic"]

    def named(action, cid, name, template, mention=None, **kw):
        make = _named(action, cid, name, template, **kw)
        make.mention = mention or name
        return make

    def _named(action, cid, name, template, **kw):
        def make():
            body = b.body()
            params = {} if action == "open" else {"body": body}
            return template.format(n=name, b=body), ex(MSG_INTENT[action], msg_target(action, cid), params, **kw), {}
        return make

    def add_named(make, **kw):
        b.add(make, mention=make.mention, **kw)

    # Basic, canonical names: 14 send, 8 draft, 6 open.
    for action, count in (("send", 14), ("draft", 8), ("open", 6)):
        for i in range(count):
            cid = rotate(basic, i + len(action))
            tpl = rotate(T[action], i % len(basic) + i // len(basic))
            add_named(named(action, cid, spoken(ents[cid], locale), tpl), tag="basic")

    # Noise on canonical requests: 5 each.
    asr_pool = pool["asr"]
    actions = ["send", "draft", "open", "send", "draft"]
    for i, action in enumerate(actions):
        cid = rotate(basic, i + 3)
        name = spoken(ents[cid], locale)
        typo_tpl = rotate(T[action], i)
        if en:
            add_named(named(action, cid, en_typo(name), typo_tpl), tag="noise", noise="typo", difficulty="medium")
        else:
            def make(action=action, cid=cid, name=name, tpl=typo_tpl):
                body = b.body()
                params = {} if action == "open" else {"body": body}
                return ja_typo(tpl.format(n=name, b=body)), ex(MSG_INTENT[action], msg_target(action, cid), params), {}
            b.add(make, tag="noise", noise="typo", difficulty="medium", mention=name)
        acid = rotate(asr_pool, i)
        add_named(named(action, acid, ASR_VARIANTS[spoken(ents[acid], locale)], rotate(T[action], i + 1)),
                  tag="noise", noise="asr_homophone", difficulty="medium")
        for kind in ("code_switch", "word_order"):
            add_named(named(action, rotate(basic, i + 5), spoken(ents[rotate(basic, i + 5)], locale), MSG_NOISE[locale][kind][action]),
                      tag="noise", noise=kind, difficulty="medium")

    # Aliases, nicknames and orthographic variants (表記ゆれ): 8.
    for i, (action, cid, fi) in enumerate(pool["alias"]):
        add_named(named(action, cid, spoken(ents[cid], locale, fi), rotate(T[action], i)),
                  tag="alias", adversarial=True, difficulty="medium")

    # Same-name contacts: 6 with a disambiguating qualifier, 6 ambiguous (asking is correct).
    same = pool["same"]
    same_name = spoken(ents[same[0]], locale)
    for i in range(6):
        action = ["send", "draft", "open"][i % 3]
        cid = same[i % 2]
        qual = ents[cid]["qualifiers"][0]
        if en:
            phrase = f"{same_name} {pool['qual_phrase'][qual]}"
        else:
            phrase = f"{qual}の{same_name}"
        add_named(named(action, cid, phrase, rotate(T[action], i), mention=same_name),
                  tag="same_name_qualified", adversarial=True, difficulty="hard")
    for i in range(6):
        action = ["send", "draft", "open"][i % 3]
        cands = [msg_target(action, c) for c in same]
        add_named(named(action, None, same_name, rotate(T[action], i), resolution="disambiguate", candidates=cands),
                  tag="same_name_ambiguous", adversarial=True, difficulty="hard")

    # Homophones / sound-alike names: 6. Plan entries: (action, phrase, target, candidates, mention).
    for i, (action, name, cid, cands, mention) in enumerate(pool["homophone"]):
        if cid:
            add_named(named(action, cid, name, rotate(T[action], i), mention=mention),
                      tag="homophone", adversarial=True, difficulty="hard")
        else:
            add_named(named(action, None, name, rotate(T[action], i), mention=mention, resolution="disambiguate",
                            candidates=[msg_target(action, c) for c in cands]),
                      tag="homophone", adversarial=True, difficulty="hard")

    # On-screen references: 14.
    msgs = pool.get("msgs") or [e["id"] for e in catalog["entities"] if e["type"] == "MessageEntity" and e["locale"] == locale]
    ordinals = EN_ORDINALS if en else JA_ORDINALS
    screen_templates = {
        "en-US": {"contact_ord": ["Send the {o} contact a message saying {b}", "Text the {o} person saying {b}",
                                  "Draft a message to the {o} contact saying {b}"],
                  "contact_this": ["Send this person a message saying {b}", "Draft a message to this contact saying {b}"],
                  "conv_ord": ["Open the {o} conversation", "Open the {o} chat"],
                  "mark": ["Mark this as read", "Mark this message as read", "Mark this one as read"],
                  "reply": ["Reply to this saying {b}", "Reply to this one saying {b}"],
                  "ambiguous": ["Send this person a message saying {b}", "Text this person saying {b}"]},
        "ja-JP": {"contact_ord": ["{o}の人に「{b}」って送って", "{o}の人へ「{b}」と送信して",
                                  "{o}の人宛てに「{b}」の下書きを作って"],
                  "contact_this": ["この人に「{b}」って送って", "この人宛てに「{b}」の下書きを作って"],
                  "conv_ord": ["{o}の会話を開いて", "{o}のトークを開いて"],
                  "mark": ["これを既読にして", "このメッセージを既読にして", "これ既読にしといて"],
                  "reply": ["これに「{b}」って返信して", "このメッセージに「{b}」って返信して"],
                  "ambiguous": ["この人に「{b}」って送って", "この人へ「{b}」と送信して"]},
    }[locale]

    def screen_case(template, screen, visible, intent, entity_id, params_body=True, **kw):
        def make():
            body = b.body()
            utterance = template.format(b=body)
            params = {"body": body} if params_body else {}
            if intent == "SetMessageReadStatusIntent":
                params = {"is_read": True}
            return utterance, ex(intent, entity_id, params, **kw), {"screen": screen, "visible_entities": visible}
        return make

    for i in range(3):
        visible = [rotate(basic, i + k) for k in range(3)]
        o, idx = ordinals[i if i < 2 else 3]
        tpl = screen_templates["contact_ord"][i]
        intent = "DraftMessageIntent" if "raft" in tpl or "下書き" in tpl else "SendMessageIntent"
        b.add(screen_case(tpl.replace("{o}", o), "contact_list", visible, intent, visible[idx]),
              tag="screen", adversarial=True, difficulty="medium")
    for i in range(2):
        cid = rotate(basic, i + 4)
        tpl = screen_templates["contact_this"][i]
        intent = "DraftMessageIntent" if i == 1 else "SendMessageIntent"
        b.add(screen_case(tpl, "contact_detail", [cid], intent, cid), tag="screen", adversarial=True, difficulty="medium")
    for i in range(2):
        visible = ["conv_" + rotate(basic, i + k + 2) for k in range(3)]
        o, idx = ordinals[i + 1]
        b.add(screen_case(screen_templates["conv_ord"][i].replace("{o}", o), "conversation_list", visible,
                          "OpenConversationIntent", visible[idx], params_body=False),
              tag="screen", adversarial=True, difficulty="medium")
    for i in range(3):
        mid = msgs[i]
        b.add(screen_case(screen_templates["mark"][i], "message_detail", [mid], "SetMessageReadStatusIntent", mid),
              tag="screen", adversarial=True, difficulty="medium")
    for i in range(2):
        mid = msgs[i + 3]
        sender = ents[mid]["related"]["sender"]
        b.add(screen_case(screen_templates["reply"][i], "message_detail", [mid], "SendMessageIntent", sender),
              tag="screen", adversarial=True, difficulty="hard")
    for i in range(2):
        visible = [rotate(basic, i + k + 1) for k in range(3)]
        b.add(screen_case(screen_templates["ambiguous"][i], "contact_list", visible, "SendMessageIntent", None,
                          resolution="disambiguate", candidates=visible),
              tag="screen_ambiguous", adversarial=True, difficulty="hard")

    # Multi-turn carry-over: 12.
    mt = {
        "en-US": [("open", "Send them a message saying {b}", "send"), ("open", "Draft one to them saying {b}", "draft"),
                  ("send", "Send them another one saying {b}", "send"), ("send", "Open my chat with them", "open")],
        "ja-JP": [("open", "その人に「{b}」って送って", "send"), ("open", "その人宛てに「{b}」の下書きを作って", "draft"),
                  ("send", "同じ人にもう一度「{b}」って送って", "send"), ("send", "その人とのトークを開いて", "open")],
    }[locale]
    for i in range(12):
        prior_action, tpl, action = mt[i % 4]
        cid = rotate(basic, i + 2 * (i // 4))
        name = spoken(ents[cid], locale)

        def make(prior_action=prior_action, tpl=tpl, action=action, cid=cid, name=name):
            body = b.body()
            prior_utt = rotate(T[prior_action], 0).format(n=name, b=b.body())
            prior = {"utterance": prior_utt, "intent": MSG_INTENT[prior_action], "entity_id": msg_target(prior_action, cid)}
            params = {} if action == "open" else {"body": body}
            return tpl.format(b=body), ex(MSG_INTENT[action], msg_target(action, cid), params), {"prior_turn": prior}
        b.add(make, tag="multi_turn", adversarial=True, difficulty="medium")
    return b.cases


# ----------------------------- calendar ------------------------------------

CAL_TEMPLATES = {
    "en-US": {
        "create": ["Add {t} on {d} at {h}", "Schedule {t} for {d} at {h}", "Put {t} on my calendar for {d} at {h}",
                   "Create an event called {t} on {d} at {h}"],
        "update": ["Move {e} to {h}", "Reschedule {e} to {d} at {h}", "Push {e} to {h}"],
        "update_time_only": ["Move {e} to {h}", "Push {e} to {h}"],
        "delete": ["Cancel {e}", "Delete {e} from my calendar", "Remove {e}"],
        "open": ["Open {e}", "Show me {e}"],
        "share": ["Share {e} with {p}"],
    },
    "ja-JP": {
        "create": ["{d}の{h}に{t}を入れて", "{d}{h}から{t}の予定を作って", "{t}を{d}の{h}で追加して"],
        "update": ["{e}を{h}に変更して", "{e}を{h}にずらして", "{e}を{d}の{h}に移動して"],
        "update_time_only": ["{e}を{h}に変更して", "{e}を{h}にずらして"],
        "delete": ["{e}をキャンセルして", "{e}の予定を削除して", "{e}を消して"],
        "open": ["{e}を開いて", "{e}を見せて"],
        "share": ["{e}を{p}に共有して"],
    },
}
CAL_NOISE = {
    "en-US": {
        "code_switch": {"delete": "{e} を cancel して", "update": "Move {e} to {h}, よろしく",
                        "share": "{e} を {p} に share して", "create": "Add {t} on {d} at {h} の予定", "open": "Please 開いて {e}"},
        "word_order": {"delete": "{e}, cancel that", "update": "To {h}, move {e}", "share": "With {p}, share {e}",
                       "create": "On {d} at {h}, add {t}", "open": "{e}, open that"},
    },
    "ja-JP": {
        "code_switch": {"delete": "{e}をcancelして", "update": "{e}を{h}にrescheduleして", "share": "{e}を{p}にshareして",
                        "create": "{d}の{h}に{t}をaddして", "open": "{e}をopenして"},
        "word_order": {"delete": "キャンセルして、{e}", "update": "{h}に変更して、{e}を", "share": "共有して、{e}を{p}に",
                       "create": "入れて、{d}の{h}に{t}", "open": "開いて、{e}を"},
    },
}
CAL_INTENT = {"create": "CreateEventIntent", "update": "UpdateEventIntent", "delete": "DeleteEventIntent",
              "open": "OpenEventIntent", "share": "ShareEventIntent"}


def calendar_cases(locale, rnd, catalog, pool=None, b=None):
    pool = pool or CALENDAR_POOLS[("v0", locale)]
    b = b or Builder("calendar", locale, rnd)
    ents = by_id(catalog["entities"])
    T = CAL_TEMPLATES[locale]
    en = locale == "en-US"
    basic = pool["basic"]

    def params_for(action, h=None, d=None, p=None, t=None):
        if action == "create":
            return {"title": t, "day": d, "time": h}
        if action == "update":
            return {k: v for k, v in (("time", h), ("day", d)) if v is not None}
        if action == "share":
            return {"invitee": p}
        return {}

    def fill(template, action, e=None, eid=None, *, state=None, mention=None, **kw):
        make = _fill(template, action, e, eid, state=state, **kw)
        make.mention = mention if mention is not None else e
        return make

    def add(make, **kw):
        b.add(make, mention=make.mention, **kw)

    def _fill(template, action, e=None, eid=None, *, state=None, **kw):
        def make():
            h, d, p, t = b.time(), b.day(), b.invitee(), b.rnd.choice(NEW_TITLES[locale])
            uses_day = "{d}" in template
            utterance = template.format(e=e or "", h=h, d=d, p=p, t=t)
            params = params_for(action, h if "{h}" in template else None, d if uses_day else None,
                                p if "{p}" in template else None, t)
            return utterance, ex(CAL_INTENT[action], eid, params, **kw), dict(state or {})
        return make

    # Basic: 10 create, 6 update, 6 delete, 3 open, 3 share.
    for i in range(10):
        add(fill(rotate(T["create"], i), "create"), tag="basic")
    for action, count in (("update", 6), ("delete", 6), ("open", 3), ("share", 3)):
        for i in range(count):
            eid = rotate(basic, i + len(action))
            add(fill(rotate(T[action], i % len(basic) + i // len(basic)), action, spoken(ents[eid], locale), eid), tag="basic")

    # Noise: 5 each.
    asr_pool = pool["asr"]
    noise_actions = ["delete", "update", "share", "open", "delete"]
    for i, action in enumerate(noise_actions):
        eid = rotate(basic, i + 2)
        name = spoken(ents[eid], locale)
        tpl = rotate(T[action], i)
        if en:
            add(fill(tpl, action, en_typo(name), eid), tag="noise", noise="typo", difficulty="medium")
        else:
            def make(tpl=tpl, action=action, name=name, eid=eid):
                utterance, expected, state = fill(tpl, action, name, eid)()
                return ja_typo(utterance), expected, state
            b.add(make, tag="noise", noise="typo", difficulty="medium", mention=name)
        aid = rotate(asr_pool, i)
        add(fill(rotate(T[action], i + 1), action, ASR_VARIANTS[spoken(ents[aid], locale)], aid),
              tag="noise", noise="asr_homophone", difficulty="medium")
    for i, action in enumerate(["delete", "update", "share", "create", "open"]):
        for kind in ("code_switch", "word_order"):
            eid = None if action == "create" else rotate(basic, i + 4)
            add(fill(CAL_NOISE[locale][kind][action], action, spoken(ents[eid], locale) if eid else None, eid),
                  tag="noise", noise=kind, difficulty="medium")

    # Aliases / abbreviations / 表記ゆれ: 8.
    for action, eid, fi, tpl in pool["alias"]:
        add(fill(tpl, action, spoken(ents[eid], locale, fi), eid), tag="alias", adversarial=True, difficulty="medium")

    # Same-title events: 6 qualified, 6 ambiguous.
    same = pool["same"]
    title = spoken(ents[same[0]], locale)
    for action, eid, tpl in pool["qualified"]:
        add(fill(tpl, action, None, eid, mention=title), tag="same_name_qualified", adversarial=True, difficulty="hard")
    for i, action in enumerate(["delete", "update", "open", "delete", "share", "update"]):
        tpl = rotate(T["update_time_only"] if action == "update" else T[action], i // 3)
        add(fill(tpl, action, title, None, resolution="disambiguate", candidates=same),
              tag="same_name_ambiguous", adversarial=True, difficulty="hard")

    # Homophones: 6.
    pair = pool["pair"]
    for action, tpl, eid, mention in pool["homophone"]:
        if eid:
            add(fill(tpl, action, None, eid, mention=mention), tag="homophone", adversarial=True, difficulty="hard")
        else:
            add(fill(tpl, action, None, None, mention=mention, resolution="disambiguate", candidates=pair),
                tag="homophone", adversarial=True, difficulty="hard")

    # On-screen references: 6 day view ordinals, 6 event detail, 2 ambiguous.
    ordinals = EN_ORDINALS if en else JA_ORDINALS
    day_tpl = ({"update": "Move the {o} one to {h}", "delete": "Cancel the {o} one", "open": "Open the {o} one",
                "share": "Share the {o} one with {p}"} if en else
               {"update": "{o}の予定を{h}に変更して", "delete": "{o}の予定をキャンセルして", "open": "{o}の予定を開いて",
                "share": "{o}の予定を{p}に共有して"})
    detail_tpl = ([("delete", "Delete this"), ("update", "Move this to {h}"), ("share", "Share this with {p}"),
                   ("delete", "Cancel this event"), ("update", "Push this to {h}"), ("share", "Share this event with {p}")] if en else
                  [("delete", "この予定を削除して"), ("update", "これを{h}に変更して"), ("share", "これを{p}に共有して"),
                   ("delete", "この予定をキャンセルして"), ("update", "これを{h}にずらして"), ("share", "この予定を{p}に共有して")])
    for i, action in enumerate(["update", "delete", "open", "share", "delete", "update"]):
        visible = [rotate(basic, i + k) for k in range(3)]
        o, idx = rotate(ordinals, i)
        add(fill(day_tpl[action].replace("{o}", o), action, None, visible[idx],
                   state={"screen": "day_view", "visible_entities": visible}),
              tag="screen", adversarial=True, difficulty="medium")
    for i, (action, tpl) in enumerate(detail_tpl):
        eid = rotate(basic, i + 1)
        add(fill(tpl, action, None, eid, state={"screen": "event_detail", "visible_entities": [eid]}),
              tag="screen", adversarial=True, difficulty="medium")
    for i in range(2):
        visible = [rotate(basic, i + k + 3) for k in range(3)]
        tpl = ["Cancel this", "Delete this one"][i] if en else ["これをキャンセルして", "これを削除して"][i]
        add(fill(tpl, "delete", None, None, state={"screen": "day_view", "visible_entities": visible},
                   resolution="disambiguate", candidates=visible),
              tag="screen_ambiguous", adversarial=True, difficulty="hard")

    # Multi-turn: 12.
    mt = ([("open", "Move it to {h}", "update"), ("open", "Cancel it", "delete"), ("open", "Share it with {p}", "share"),
           ("update", "Actually, cancel it", "delete")] if en else
          [("open", "それを{h}に変更して", "update"), ("open", "それをキャンセルして", "delete"),
           ("open", "それを{p}に共有して", "share"), ("update", "やっぱりそれをキャンセルして", "delete")])
    for i in range(12):
        prior_action, tpl, action = mt[i % 4]
        eid = rotate(basic, i + 2 * (i // 4))
        name = spoken(ents[eid], locale)

        def make(prior_action=prior_action, tpl=tpl, action=action, eid=eid, name=name):
            prior_tpl = T["update_time_only"][0] if prior_action == "update" else T[prior_action][0]
            prior = {"utterance": prior_tpl.format(e=name, h=b.time()), "intent": CAL_INTENT[prior_action], "entity_id": eid}
            utterance, expected, _ = fill(tpl, action, None, eid)()
            return utterance, expected, {"prior_turn": prior}
        b.add(make, tag="multi_turn", adversarial=True, difficulty="medium")
    return b.cases


# ---------------------------------------------------------------------------
# Entity pools. "v0" reproduces the Phase 1 dataset exactly; "B" and "C" are the v1 additions.
# ---------------------------------------------------------------------------

MESSAGE_POOLS = {
    ("v0", "en-US"): {
        "basic": ["c_alex", "c_anjali", "c_shawn", "c_kate", "c_marcus", "c_dani", "c_omar", "c_rae"],
        "asr": ["c_shawn", "c_kate", "c_marcus", "c_rae"],
        "alias": [("send", "c_alex", 1), ("send", "c_kate", 1), ("send", "c_kate", 2), ("draft", "c_dani", 1),
                  ("open", "c_anjali", 1), ("send", "c_omar", 1), ("send", "c_rae", 1), ("draft", "c_marcus", 1)],
        "same": ["c_samlee_work", "c_samlee_gym"], "qual_phrase": {"work": "from work", "gym": "from the gym"},
        "homophone": [("send", "John Parke", None, ["c_jon_park", "c_john_parke"], "John Parke"),
                      ("send", "Jon Park", None, ["c_jon_park", "c_john_parke"], "Jon Park"),
                      ("open", "John Parke", None, ["c_jon_park", "c_john_parke"], "John Parke"),
                      ("send", "John Parke from finance", "c_john_parke", [], "John Parke"),
                      ("send", "Jon Park from design", "c_jon_park", [], "Jon Park"),
                      ("draft", "John Parke from finance", "c_john_parke", [], "John Parke")],
    },
    ("v0", "ja-JP"): {
        "basic": ["j_sato", "j_saito", "j_onodera", "j_ishikawa", "j_fujii"],
        "asr": ["j_sato", "j_takase"],
        "alias": [("send", "j_saito", 1), ("send", "j_saito", 2), ("send", "j_ishikawa", 1), ("open", "j_ishikawa", 1),
                  ("send", "j_sato", 1), ("draft", "j_saito", 1), ("open", "j_saito", 2), ("draft", "j_sato", 1)],
        "same": ["j_nakamura_work", "j_nakamura_uni"],
        "homophone": [("send", "みづき", None, ["j_takase", "j_mori"], "みづき"),
                      ("send", "美月", None, ["j_takase", "j_mori"], "美月"),
                      ("open", "瑞希", None, ["j_takase", "j_mori"], "瑞希"),
                      ("send", "加藤涼", None, ["j_kato_tennis", "j_kato_acct"], "加藤涼"),
                      ("send", "経理の加藤遼", "j_kato_acct", [], "加藤遼"),
                      ("draft", "高瀬美月", "j_takase", [], "高瀬美月")],
    },
    ("B", "en-US"): {
        "basic": ["c_nadia", "c_tomasz", "c_leila", "c_hugo", "c_grace", "c_ivan", "c_mei", "c_felix"],
        "asr": ["c_tomasz", "c_leila", "c_grace", "c_felix"],
        "alias": [("send", "c_nadia", 1), ("send", "c_tomasz", 1), ("draft", "c_grace", 1), ("open", "c_leila", 1),
                  ("send", "c_hugo", 1), ("send", "c_ivan", 1), ("draft", "c_mei", 1), ("send", "c_felix", 1)],
        "same": ["c_chris_studio", "c_chris_neighbor"], "qual_phrase": {"studio": "from the studio", "neighbor": "my neighbor"},
        "homophone": [("send", "Mark Ellison", None, ["c_marc_ellison", "c_mark_ellison"], "Mark Ellison"),
                      ("send", "Marc Ellison", None, ["c_marc_ellison", "c_mark_ellison"], "Marc Ellison"),
                      ("open", "Mark Ellison", None, ["c_marc_ellison", "c_mark_ellison"], "Mark Ellison"),
                      ("send", "Mark Ellison from school", "c_mark_ellison", [], "Mark Ellison"),
                      ("send", "Marc Ellison from the band", "c_marc_ellison", [], "Marc Ellison"),
                      ("draft", "Mark Ellison from school", "c_mark_ellison", [], "Mark Ellison")],
        "msgs": ["msg_en_b1", "msg_en_b2", "msg_en_b3", "msg_en_b4", "msg_en_b5", "msg_en_b6"],
    },
    ("C", "en-US"): {
        "basic": ["c_rosa", "c_kwame", "c_elena", "c_dmitri", "c_sofia", "c_arjun", "c_yusuf", "c_clara"],
        "asr": ["c_kwame", "c_arjun", "c_yusuf", "c_clara"],
        "alias": [("send", "c_rosa", 1), ("send", "c_elena", 1), ("draft", "c_dmitri", 1), ("open", "c_sofia", 1),
                  ("send", "c_kwame", 1), ("draft", "c_arjun", 1), ("send", "c_yusuf", 1), ("open", "c_clara", 1)],
        "same": ["c_jordan_climb", "c_jordan_acct"], "qual_phrase": {"climbing": "from climbing", "accounting": "from accounting"},
        "homophone": [("send", "Aidan Farrell", None, ["c_aidan_farrell", "c_aiden_farrell"], "Aidan Farrell"),
                      ("send", "Aiden Farrell", None, ["c_aidan_farrell", "c_aiden_farrell"], "Aiden Farrell"),
                      ("open", "Aidan Farrell", None, ["c_aidan_farrell", "c_aiden_farrell"], "Aidan Farrell"),
                      ("send", "Aiden Farrell from legal", "c_aiden_farrell", [], "Aiden Farrell"),
                      ("send", "Aidan Farrell from soccer", "c_aidan_farrell", [], "Aidan Farrell"),
                      ("draft", "Aiden Farrell from legal", "c_aiden_farrell", [], "Aiden Farrell")],
        "msgs": ["msg_en_c1", "msg_en_c2", "msg_en_c3", "msg_en_c4", "msg_en_c5", "msg_en_c6"],
    },
    ("B", "ja-JP"): {
        "basic": ["j_sakamoto", "j_hirano", "j_yoshikawa", "j_matsuda", "j_okamoto"],
        "asr": ["j_sakamoto", "j_hirano"],
        "alias": [("send", "j_watanabe", 1), ("send", "j_watanabe", 2), ("send", "j_yoshikawa", 1), ("open", "j_yoshikawa", 1),
                  ("draft", "j_watanabe", 2), ("draft", "j_yoshikawa", 1), ("open", "j_watanabe", 1), ("send", "j_yoshikawa", 1)],
        "same": ["j_yamada_gym", "j_yamada_client"],
        "homophone": [("send", "はるか", None, ["j_miyamoto", "j_ishii"], "はるか"),
                      ("send", "遥", None, ["j_miyamoto", "j_ishii"], "遥"),
                      ("open", "遙", None, ["j_miyamoto", "j_ishii"], "遙"),
                      ("send", "佐々木翔太", None, ["j_sasaki_baito", "j_sasaki_lab"], "佐々木翔太"),
                      ("send", "研究室の佐々木将太", "j_sasaki_lab", [], "佐々木将太"),
                      ("draft", "宮本遥", "j_miyamoto", [], "宮本遥")],
        "msgs": ["msg_ja_b1", "msg_ja_b2", "msg_ja_b3", "msg_ja_b4", "msg_ja_b5", "msg_ja_b6"],
    },
    ("C", "ja-JP"): {
        "basic": ["j_murakami", "j_nishida", "j_hara", "j_kanno", "j_shibata"],
        "asr": ["j_murakami", "j_hara"],
        "alias": [("send", "j_takagi", 1), ("send", "j_nishida", 1), ("open", "j_nishida", 1), ("draft", "j_takagi", 1),
                  ("open", "j_takagi", 1), ("send", "j_nishida", 1), ("draft", "j_nishida", 1), ("send", "j_takagi", 1)],
        "same": ["j_kobayashi_yoga", "j_kobayashi_nursery"],
        "homophone": [("send", "あや", None, ["j_kitamura", "j_minami"], "あや"),
                      ("send", "彩", None, ["j_kitamura", "j_minami"], "彩"),
                      ("open", "綾", None, ["j_kitamura", "j_minami"], "綾"),
                      ("send", "長谷川亮", None, ["j_hasegawa_futsal", "j_hasegawa_soumu"], "長谷川亮"),
                      ("send", "総務の長谷川良", "j_hasegawa_soumu", [], "長谷川良"),
                      ("draft", "北村彩", "j_kitamura", [], "北村彩")],
        "msgs": ["msg_ja_c1", "msg_ja_c2", "msg_ja_c3", "msg_ja_c4", "msg_ja_c5", "msg_ja_c6"],
    },
}

CALENDAR_POOLS = {
    ("v0", "en-US"): {
        "basic": ["ev_design_review", "ev_peer_review", "ev_qbr", "ev_standup", "ev_demo", "ev_onboarding", "ev_budget", "ev_brake"],
        "asr": ["ev_design_review", "ev_peer_review", "ev_onboarding", "ev_brake"],
        "alias": [("delete", "ev_qbr", 1, "Cancel the {e}"), ("update", "ev_standup", 1, "Move {e} to {h}"),
                  ("open", "ev_design_review", 1, "Open {e}"), ("update", "ev_standup", 2, "Push the {e} to {h}"),
                  ("share", "ev_onboarding", 1, "Share {e} with {p}"), ("delete", "ev_qbr", 1, "Delete {e} from my calendar"),
                  ("open", "ev_standup", 1, "Show me the {e}"), ("update", "ev_design_review", 1, "Reschedule {e} to {d} at {h}")],
        "same": ["ev_sync_mon", "ev_sync_thu"],
        "qualified": [("update", "ev_sync_thu", "Move Thursday's Team Sync to {h}"), ("delete", "ev_sync_mon", "Cancel the Monday Team Sync"),
                      ("open", "ev_sync_thu", "Open Team Sync on Thursday"), ("delete", "ev_sync_mon", "Delete Monday's Team Sync"),
                      ("share", "ev_sync_thu", "Share Thursday's Team Sync with {p}"), ("update", "ev_sync_mon", "Push the Monday Team Sync to {h}")],
        "pair": ["ev_jon_bday", "ev_john_bday"],
        "homophone": [("delete", "Cancel John's Birthday Dinner", None, "John's Birthday Dinner"),
                      ("open", "Open Jon's Birthday Dinner", None, "Jon's Birthday Dinner"),
                      ("update", "Move John's Birthday Dinner to {h}", None, "John's Birthday Dinner"),
                      ("open", "Open John's Birthday Dinner on Saturday", "ev_john_bday", "John's Birthday Dinner"),
                      ("update", "Move Jon's Birthday Dinner on Friday to {h}", "ev_jon_bday", "Jon's Birthday Dinner"),
                      ("share", "Share John's Birthday Dinner on Saturday with {p}", "ev_john_bday", "John's Birthday Dinner")],
    },
    ("v0", "ja-JP"): {
        "basic": ["jev_design", "jev_zensha", "jev_torihiki", "jev_yosan", "jev_kenshu", "jev_kangeikai", "jev_tanaoroshi", "jev_setsumeikai"],
        "asr": ["jev_tanaoroshi", "jev_setsumeikai"],
        "alias": [("delete", "jev_design", 1, "{e}をキャンセルして"), ("update", "jev_zensha", 1, "{e}を{h}に変更して"),
                  ("open", "jev_torihiki", 1, "{e}を開いて"), ("delete", "jev_torihiki", 2, "{e}の予定を削除して"),
                  ("open", "jev_kenshu", 1, "{e}を見せて"), ("share", "jev_design", 1, "{e}を{p}に共有して"),
                  ("open", "jev_zensha", 1, "{e}を開いて"), ("update", "jev_torihiki", 1, "{e}を{h}にずらして")],
        "same": ["jev_teirei_mon", "jev_teirei_thu"],
        "qualified": [("update", "jev_teirei_thu", "木曜のチーム定例を{h}に変更して"), ("delete", "jev_teirei_mon", "月曜のチーム定例をキャンセルして"),
                      ("open", "jev_teirei_thu", "木曜のチーム定例を開いて"), ("share", "jev_teirei_mon", "月曜のチーム定例を{p}に共有して"),
                      ("delete", "jev_teirei_thu", "木曜のチーム定例の予定を削除して"), ("update", "jev_teirei_mon", "月曜のチーム定例を{h}にずらして")],
        "pair": ["jev_kouen_fri", "jev_kouen_sat"],
        "homophone": [("delete", "講演をキャンセルして", None, "講演"), ("open", "こうえんの予定を開いて", None, "こうえん"),
                      ("open", "公演を見せて", None, "公演"), ("open", "金曜の講演を開いて", "jev_kouen_fri", "講演"),
                      ("delete", "土曜の公演をキャンセルして", "jev_kouen_sat", "公演"),
                      ("share", "金曜のこうえんを{p}に共有して", "jev_kouen_fri", "こうえん")],
    },
    ("B", "en-US"): {
        "basic": ["ev_roadmap", "ev_security", "ev_hiring", "ev_retro", "ev_boardprep", "ev_customer", "ev_offsite", "ev_compliance"],
        "asr": ["ev_roadmap", "ev_retro", "ev_boardprep", "ev_customer"],
        "alias": [("delete", "ev_retro", 1, "Cancel the {e}"), ("update", "ev_roadmap", 1, "Move the {e} to {h}"),
                  ("open", "ev_offsite", 1, "Open the {e}"), ("share", "ev_compliance", 1, "Share {e} with {p}"),
                  ("delete", "ev_offsite", 1, "Delete the {e} from my calendar"), ("open", "ev_retro", 1, "Show me the {e}"),
                  ("update", "ev_compliance", 1, "Push {e} to {h}"), ("delete", "ev_roadmap", 1, "Remove the {e}")],
        "same": ["ev_vendor_tue", "ev_vendor_fri"],
        "qualified": [("update", "ev_vendor_fri", "Move Friday's Vendor Sync to {h}"), ("delete", "ev_vendor_tue", "Cancel the Tuesday Vendor Sync"),
                      ("open", "ev_vendor_fri", "Open Vendor Sync on Friday"), ("delete", "ev_vendor_tue", "Delete Tuesday's Vendor Sync"),
                      ("share", "ev_vendor_fri", "Share Friday's Vendor Sync with {p}"), ("update", "ev_vendor_tue", "Push the Tuesday Vendor Sync to {h}")],
        "pair": ["ev_bryce_party", "ev_brice_party"],
        "homophone": [("delete", "Cancel Brice's Farewell Party", None, "Brice's Farewell Party"),
                      ("open", "Open Bryce's Farewell Party", None, "Bryce's Farewell Party"),
                      ("update", "Move Brice's Farewell Party to {h}", None, "Brice's Farewell Party"),
                      ("open", "Open Brice's Farewell Party on Saturday", "ev_brice_party", "Brice's Farewell Party"),
                      ("update", "Move Bryce's Farewell Party on Friday to {h}", "ev_bryce_party", "Bryce's Farewell Party"),
                      ("share", "Share Brice's Farewell Party on Saturday with {p}", "ev_brice_party", "Brice's Farewell Party")],
    },
    ("C", "en-US"): {
        "basic": ["ev_sprint", "ev_townhall", "ev_migration", "ev_partner", "ev_a11y", "ev_debrief", "ev_kickoff", "ev_pottery"],
        "asr": ["ev_townhall", "ev_migration", "ev_partner", "ev_a11y"],
        "alias": [("delete", "ev_townhall", 1, "Cancel the {e}"), ("update", "ev_sprint", 1, "Move {e} to {h}"),
                  ("open", "ev_a11y", 1, "Open the {e}"), ("share", "ev_debrief", 1, "Share the {e} with {p}"),
                  ("delete", "ev_kickoff", 1, "Delete the {e} from my calendar"), ("open", "ev_townhall", 1, "Show me the {e}"),
                  ("update", "ev_kickoff", 1, "Push the {e} to {h}"), ("delete", "ev_a11y", 1, "Remove the {e}")],
        "same": ["ev_designsync_mon", "ev_designsync_wed"],
        "qualified": [("update", "ev_designsync_wed", "Move Wednesday's Design Sync to {h}"), ("delete", "ev_designsync_mon", "Cancel the Monday Design Sync"),
                      ("open", "ev_designsync_wed", "Open Design Sync on Wednesday"), ("delete", "ev_designsync_mon", "Delete Monday's Design Sync"),
                      ("share", "ev_designsync_wed", "Share Wednesday's Design Sync with {p}"), ("update", "ev_designsync_mon", "Push the Monday Design Sync to {h}")],
        "pair": ["ev_neil_lunch", "ev_neal_lunch"],
        "homophone": [("delete", "Cancel Neal's Retirement Lunch", None, "Neal's Retirement Lunch"),
                      ("open", "Open Neil's Retirement Lunch", None, "Neil's Retirement Lunch"),
                      ("update", "Move Neal's Retirement Lunch to {h}", None, "Neal's Retirement Lunch"),
                      ("open", "Open Neal's Retirement Lunch on Friday", "ev_neal_lunch", "Neal's Retirement Lunch"),
                      ("update", "Move Neil's Retirement Lunch on Thursday to {h}", "ev_neil_lunch", "Neil's Retirement Lunch"),
                      ("share", "Share Neal's Retirement Lunch on Friday with {p}", "ev_neal_lunch", "Neal's Retirement Lunch")],
    },
    ("B", "ja-JP"): {
        "basic": ["jev_roadmap", "jev_security", "jev_saiyou", "jev_furikaeri", "jev_yakuin", "jev_kokyaku", "jev_gasshuku", "jev_compliance"],
        "asr": ["jev_saiyou", "jev_yakuin", "jev_kokyaku"],
        "alias": [("delete", "jev_roadmap", 1, "{e}をキャンセルして"), ("update", "jev_security", 1, "{e}を{h}に変更して"),
                  ("open", "jev_furikaeri", 1, "{e}を開いて"), ("delete", "jev_security", 1, "{e}の予定を削除して"),
                  ("open", "jev_roadmap", 1, "{e}を見せて"), ("share", "jev_furikaeri", 1, "{e}を{p}に共有して"),
                  ("update", "jev_roadmap", 1, "{e}を{h}にずらして"), ("open", "jev_security", 1, "{e}を開いて")],
        "same": ["jev_bukai_tue", "jev_bukai_fri"],
        "qualified": [("update", "jev_bukai_fri", "金曜の部会を{h}に変更して"), ("delete", "jev_bukai_tue", "火曜の部会をキャンセルして"),
                      ("open", "jev_bukai_fri", "金曜の部会を開いて"), ("share", "jev_bukai_tue", "火曜の部会を{p}に共有して"),
                      ("delete", "jev_bukai_fri", "金曜の部会の予定を削除して"), ("update", "jev_bukai_tue", "火曜の部会を{h}にずらして")],
        "pair": ["jev_seisan_tue", "jev_seisan_thu"],
        "homophone": [("delete", "精算会をキャンセルして", None, "精算会"), ("open", "せいさんかいの予定を開いて", None, "せいさんかい"),
                      ("open", "清算会を見せて", None, "清算会"), ("open", "火曜の精算会を開いて", "jev_seisan_tue", "精算会"),
                      ("delete", "木曜の清算会をキャンセルして", "jev_seisan_thu", "清算会"),
                      ("share", "火曜のせいさんかいを{p}に共有して", "jev_seisan_tue", "せいさんかい")],
    },
    ("C", "ja-JP"): {
        "basic": ["jev_ikou", "jev_choukai", "jev_partner", "jev_access", "jev_mendan", "jev_kickoff", "jev_tougei", "jev_benkyou"],
        "asr": ["jev_ikou", "jev_choukai", "jev_benkyou"],
        "alias": [("delete", "jev_choukai", 1, "{e}をキャンセルして"), ("update", "jev_access", 1, "{e}を{h}に変更して"),
                  ("open", "jev_choukai", 1, "{e}を開いて"), ("delete", "jev_access", 1, "{e}の予定を削除して"),
                  ("open", "jev_access", 1, "{e}を見せて"), ("share", "jev_choukai", 1, "{e}を{p}に共有して"),
                  ("update", "jev_choukai", 1, "{e}を{h}にずらして"), ("share", "jev_access", 1, "{e}を{p}に共有して")],
        "same": ["jev_weekly_mon", "jev_weekly_wed"],
        "qualified": [("update", "jev_weekly_wed", "水曜の週次レビューを{h}に変更して"), ("delete", "jev_weekly_mon", "月曜の週次レビューをキャンセルして"),
                      ("open", "jev_weekly_wed", "水曜の週次レビューを開いて"), ("share", "jev_weekly_mon", "月曜の週次レビューを{p}に共有して"),
                      ("delete", "jev_weekly_wed", "水曜の週次レビューの予定を削除して"), ("update", "jev_weekly_mon", "月曜の週次レビューを{h}にずらして")],
        "pair": ["jev_kansou_thu", "jev_kansou_fri"],
        "homophone": [("delete", "感想会をキャンセルして", None, "感想会"), ("open", "かんそうかいの予定を開いて", None, "かんそうかい"),
                      ("open", "歓送会を見せて", None, "歓送会"), ("open", "木曜の感想会を開いて", "jev_kansou_thu", "感想会"),
                      ("delete", "金曜の歓送会をキャンセルして", "jev_kansou_fri", "歓送会"),
                      ("share", "木曜のかんそうかいを{p}に共有して", "jev_kansou_thu", "かんそうかい")],
    },
}

# v1 synthetic entities (all invented for this benchmark).
V1_CONTACTS = [
    contact("c_nadia", "Nadia Kowalski", ["Nadia"]), contact("c_tomasz", "Tomasz Brennan", ["Tom"]),
    contact("c_leila", "Leila Farouk", ["Leila"]), contact("c_hugo", "Hugo Lambert", ["Hugo"]),
    contact("c_grace", "Grace Okafor", ["Gracie"]), contact("c_ivan", "Ivan Sorensen", ["Ivan"]),
    contact("c_mei", "Mei Lindgren", ["Mei"]), contact("c_felix", "Felix Moreau", ["Felix"]),
    contact("c_chris_studio", "Chris Moreno", qualifiers=["studio"]), contact("c_chris_neighbor", "Chris Moreno", qualifiers=["neighbor"]),
    contact("c_marc_ellison", "Marc Ellison", qualifiers=["band"]), contact("c_mark_ellison", "Mark Ellison", qualifiers=["school"]),
    contact("c_rosa", "Rosa Delgado", ["Rosa"]), contact("c_kwame", "Kwame Mensah", ["Kwame"]),
    contact("c_elena", "Elena Novak", ["Ellie"]), contact("c_dmitri", "Dmitri Volkov", ["Mitya"]),
    contact("c_sofia", "Sofia Brandt", ["Sofie"]), contact("c_arjun", "Arjun Mehta", ["Arjun"]),
    contact("c_yusuf", "Yusuf Tekinalp", ["Yusuf"]), contact("c_clara", "Clara Holm", ["Clara"]),
    contact("c_jordan_climb", "Jordan Blake", qualifiers=["climbing"]), contact("c_jordan_acct", "Jordan Blake", qualifiers=["accounting"]),
    contact("c_aidan_farrell", "Aidan Farrell", qualifiers=["soccer"]), contact("c_aiden_farrell", "Aiden Farrell", qualifiers=["legal"]),
    contact("j_sakamoto", "坂本 陸", reading="さかもと りく", locale="ja-JP"),
    contact("j_hirano", "平野 紗季", reading="ひらの さき", locale="ja-JP"),
    contact("j_yoshikawa", "吉川 湊", [("ミナト", "みなと")], "よしかわ みなと", locale="ja-JP"),
    contact("j_matsuda", "松田 杏", reading="まつだ あん", locale="ja-JP"),
    contact("j_okamoto", "岡本 樹", reading="おかもと いつき", locale="ja-JP"),
    contact("j_watanabe", "渡邉 翔", [("渡辺 翔", "わたなべ しょう"), ("渡邊 翔", "わたなべ しょう")], "わたなべ しょう", locale="ja-JP"),
    contact("j_miyamoto", "宮本 遥", [("遥", "はるか")], "みやもと はるか", locale="ja-JP"),
    contact("j_ishii", "石井 遙", [("遙", "はるか")], "いしい はるか", locale="ja-JP"),
    contact("j_yamada_gym", "山田 翼", reading="やまだ つばさ", qualifiers=["ジム"], locale="ja-JP"),
    contact("j_yamada_client", "山田 翼", reading="やまだ つばさ", qualifiers=["取引先"], locale="ja-JP"),
    contact("j_sasaki_baito", "佐々木 翔太", reading="ささき しょうた", qualifiers=["バイト"], locale="ja-JP"),
    contact("j_sasaki_lab", "佐々木 将太", reading="ささき しょうた", qualifiers=["研究室"], locale="ja-JP"),
    contact("j_murakami", "村上 悠真", reading="むらかみ ゆうま", locale="ja-JP"),
    contact("j_nishida", "西田 楓", [("カエデ", "かえで")], "にしだ かえで", locale="ja-JP"),
    contact("j_hara", "原 颯太", reading="はら そうた", locale="ja-JP"),
    contact("j_kanno", "菅野 澪", reading="かんの みお", locale="ja-JP"),
    contact("j_shibata", "柴田 律", reading="しばた りつ", locale="ja-JP"),
    contact("j_takagi", "髙木 慎吾", [("高木 慎吾", "たかぎ しんご")], "たかぎ しんご", locale="ja-JP"),
    contact("j_kitamura", "北村 彩", [("彩", "あや")], "きたむら あや", locale="ja-JP"),
    contact("j_minami", "南 綾", [("綾", "あや")], "みなみ あや", locale="ja-JP"),
    contact("j_kobayashi_yoga", "小林 葵", reading="こばやし あおい", qualifiers=["ヨガ"], locale="ja-JP"),
    contact("j_kobayashi_nursery", "小林 葵", reading="こばやし あおい", qualifiers=["保育園"], locale="ja-JP"),
    contact("j_hasegawa_futsal", "長谷川 亮", reading="はせがわ りょう", qualifiers=["フットサル"], locale="ja-JP"),
    contact("j_hasegawa_soumu", "長谷川 良", reading="はせがわ りょう", qualifiers=["総務"], locale="ja-JP"),
]

V1_MESSAGE_SNIPPETS = {
    ("en-US", "b"): [("c_nadia", "Train is delayed again"), ("c_tomasz", "Invoice went out this morning"),
                     ("c_leila", "Can we push our call"), ("c_hugo", "Keys are under the mat"),
                     ("c_grace", "Photos from the trip"), ("c_ivan", "Table booked for eight")],
    ("en-US", "c"): [("c_rosa", "Dinner moved to seven"), ("c_kwame", "Slides look great"),
                     ("c_elena", "Parcel is at the door"), ("c_dmitri", "Running a bit behind"),
                     ("c_sofia", "Gym at six tomorrow"), ("c_arjun", "Code review is done")],
    ("ja-JP", "b"): [("j_sakamoto", "電車がまた遅れてる"), ("j_hirano", "請求書を出しました"),
                     ("j_yoshikawa", "通話を後ろにずらせる？"), ("j_matsuda", "鍵はマットの下です"),
                     ("j_okamoto", "旅行の写真です"), ("j_watanabe", "8名で予約しました")],
    ("ja-JP", "c"): [("j_murakami", "夕飯は7時からに"), ("j_nishida", "スライドいい感じ"),
                     ("j_hara", "荷物が玄関に届いた"), ("j_kanno", "少し遅れそう"),
                     ("j_shibata", "明日6時にジム"), ("j_takagi", "レビュー終わりました")],
}

V1_EVENTS = [
    event("ev_vendor_tue", "Vendor Sync", "Tuesday", "2026-11-10", "11:00", qualifiers=["tuesday", "tue"]),
    event("ev_vendor_fri", "Vendor Sync", "Friday", "2026-11-13", "11:00", qualifiers=["friday", "fri"]),
    event("ev_roadmap", "Roadmap Review", "Monday", "2026-11-09", "10:00", ["Roadmap"], qualifiers=["monday"]),
    event("ev_security", "Security Audit", "Tuesday", "2026-11-10", "14:00", qualifiers=["tuesday"]),
    event("ev_hiring", "Hiring Panel", "Wednesday", "2026-11-11", "13:00", qualifiers=["wednesday"]),
    event("ev_retro", "Launch Retro", "Thursday", "2026-11-12", "16:00", ["Retro"], qualifiers=["thursday"]),
    event("ev_boardprep", "Board Prep", "Friday", "2026-11-13", "09:00", qualifiers=["friday"]),
    event("ev_customer", "Customer Call", "Monday", "2026-11-09", "15:00", qualifiers=["monday"]),
    event("ev_offsite", "Offsite Planning", "Wednesday", "2026-11-11", "10:00", ["Offsite"], qualifiers=["wednesday"]),
    event("ev_compliance", "Compliance Training", "Thursday", "2026-11-12", "09:30", ["Compliance"], qualifiers=["thursday"]),
    event("ev_bryce_party", "Bryce's Farewell Party", "Friday", "2026-11-13", "18:00", qualifiers=["friday"], calendar="cal_personal"),
    event("ev_brice_party", "Brice's Farewell Party", "Saturday", "2026-11-14", "18:00", qualifiers=["saturday"], calendar="cal_personal"),
    event("ev_designsync_mon", "Design Sync", "Monday", "2026-11-16", "11:00", qualifiers=["monday", "mon"]),
    event("ev_designsync_wed", "Design Sync", "Wednesday", "2026-11-18", "11:00", qualifiers=["wednesday", "wed"]),
    event("ev_sprint", "Sprint Planning", "Monday", "2026-11-16", "09:00", ["Sprint Plan"], qualifiers=["monday"]),
    event("ev_townhall", "Quarterly Town Hall", "Tuesday", "2026-11-17", "16:00", ["Town Hall"], qualifiers=["tuesday"]),
    event("ev_migration", "Data Migration", "Wednesday", "2026-11-18", "20:00", qualifiers=["wednesday"]),
    event("ev_partner", "Partner Workshop", "Thursday", "2026-11-19", "13:00", qualifiers=["thursday"]),
    event("ev_a11y", "Accessibility Review", "Tuesday", "2026-11-17", "10:00", ["A11y Review"], qualifiers=["tuesday"]),
    event("ev_debrief", "Interview Debrief", "Friday", "2026-11-20", "15:00", ["Debrief"], qualifiers=["friday"]),
    event("ev_kickoff", "Project Kickoff", "Monday", "2026-11-16", "14:00", ["Kickoff"], qualifiers=["monday"]),
    event("ev_pottery", "Pottery Class", "Saturday", "2026-11-21", "10:00", qualifiers=["saturday"], calendar="cal_personal"),
    event("ev_neil_lunch", "Neil's Retirement Lunch", "Thursday", "2026-11-19", "12:00", qualifiers=["thursday"]),
    event("ev_neal_lunch", "Neal's Retirement Lunch", "Friday", "2026-11-20", "12:00", qualifiers=["friday"]),
    event("jev_bukai_tue", "部会", "火曜", "2026-11-10", "10:00", reading="ぶかい", qualifiers=["火曜"], locale="ja-JP"),
    event("jev_bukai_fri", "部会", "金曜", "2026-11-13", "10:00", reading="ぶかい", qualifiers=["金曜"], locale="ja-JP"),
    event("jev_roadmap", "ロードマップ確認", "月曜", "2026-11-09", "11:00", [("ロドマ確認", "ろどまかくにん")], "ろーどまっぷかくにん", ["月曜"], locale="ja-JP"),
    event("jev_security", "セキュリティ監査", "火曜", "2026-11-10", "14:00", [("セキュ監査", "せきゅかんさ")], "せきゅりてぃかんさ", ["火曜"], locale="ja-JP"),
    event("jev_saiyou", "採用面接", "水曜", "2026-11-11", "13:00", reading="さいようめんせつ", qualifiers=["水曜"], locale="ja-JP"),
    event("jev_furikaeri", "振り返り会", "木曜", "2026-11-12", "17:00", [("ふりかえり会", "ふりかえりかい")], "ふりかえりかい", ["木曜"], locale="ja-JP"),
    event("jev_yakuin", "役員会準備", "金曜", "2026-11-13", "09:00", reading="やくいんかいじゅんび", qualifiers=["金曜"], locale="ja-JP"),
    event("jev_kokyaku", "顧客定例", "月曜", "2026-11-09", "15:00", reading="こきゃくていれい", qualifiers=["月曜"], locale="ja-JP"),
    event("jev_gasshuku", "合宿計画", "水曜", "2026-11-11", "10:00", reading="がっしゅくけいかく", qualifiers=["水曜"], locale="ja-JP"),
    event("jev_compliance", "コンプラ研修", "木曜", "2026-11-12", "09:30", reading="こんぷらけんしゅう", qualifiers=["木曜"], locale="ja-JP"),
    event("jev_seisan_tue", "精算会", "火曜", "2026-11-10", "18:00", reading="せいさんかい", qualifiers=["火曜"], locale="ja-JP"),
    event("jev_seisan_thu", "清算会", "木曜", "2026-11-12", "18:00", reading="せいさんかい", qualifiers=["木曜"], locale="ja-JP"),
    event("jev_weekly_mon", "週次レビュー", "月曜", "2026-11-16", "10:00", reading="しゅうじれびゅー", qualifiers=["月曜"], locale="ja-JP"),
    event("jev_weekly_wed", "週次レビュー", "水曜", "2026-11-18", "10:00", reading="しゅうじれびゅー", qualifiers=["水曜"], locale="ja-JP"),
    event("jev_ikou", "移行作業", "水曜", "2026-11-18", "20:00", reading="いこうさぎょう", qualifiers=["水曜"], locale="ja-JP"),
    event("jev_choukai", "全体朝会", "月曜", "2026-11-16", "09:00", [("朝会", "ちょうかい")], "ぜんたいちょうかい", ["月曜"], locale="ja-JP"),
    event("jev_partner", "パートナー研修", "木曜", "2026-11-19", "13:00", reading="ぱーとなーけんしゅう", qualifiers=["木曜"], locale="ja-JP"),
    event("jev_access", "アクセシビリティ確認", "火曜", "2026-11-17", "10:00", [("アクセシビリティ", "あくせしびりてぃ")], "あくせしびりてぃかくにん", ["火曜"], locale="ja-JP"),
    event("jev_mendan", "面談振り返り", "金曜", "2026-11-20", "15:00", reading="めんだんふりかえり", qualifiers=["金曜"], locale="ja-JP"),
    event("jev_kickoff", "キックオフ", "月曜", "2026-11-16", "14:00", reading="きっくおふ", qualifiers=["月曜"], locale="ja-JP"),
    event("jev_tougei", "陶芸教室", "土曜", "2026-11-21", "10:00", reading="とうげいきょうしつ", qualifiers=["土曜"], calendar="cal_personal", locale="ja-JP"),
    event("jev_benkyou", "勉強会", "水曜", "2026-11-18", "19:00", reading="べんきょうかい", qualifiers=["水曜"], locale="ja-JP"),
    event("jev_kansou_thu", "感想会", "木曜", "2026-11-19", "18:00", reading="かんそうかい", qualifiers=["木曜"], locale="ja-JP"),
    event("jev_kansou_fri", "歓送会", "金曜", "2026-11-20", "18:00", reading="かんそうかい", qualifiers=["金曜"], locale="ja-JP"),
]

ASR_VARIANTS.update({
    "Tomasz Brennan": "Thomas Brennan", "Leila Farouk": "Layla Farouk", "Grace Okafor": "Grays Okafor",
    "Felix Moreau": "Felix Morrow", "Kwame Mensah": "Kwame Mensa", "Arjun Mehta": "Arjun Meta",
    "Yusuf Tekinalp": "Yousef Tekinalp", "Clara Holm": "Klara Holm",
    "坂本陸": "坂元陸", "平野紗季": "平野咲", "村上悠真": "村神悠真", "原颯太": "原壮太",
    # Some variants split or merge words; the MOCK resolver is not expected to recover all of them.
    "Roadmap Review": "Road Map Review", "Launch Retro": "Lunch Retro", "Board Prep": "Bored Prep",
    "Customer Call": "Costumer Call", "Quarterly Town Hall": "Quarterly Town Haul", "Data Migration": "Data Migrations",
    "Partner Workshop": "Partner Work Shop", "Accessibility Review": "Accessibility Revue",
    "採用面接": "再用面接", "役員会準備": "役員回準備", "顧客定例": "個客定例",
    "移行作業": "以降作業", "全体朝会": "全体町会", "勉強会": "勉強回",
})

# Paraphrase families (generator-holdout). Dev blocks use A/B, eval blocks use C/D; validate.py
# rejects any family that crosses splits.
HOLDOUT_FAMILIES = {"dev": ["A", "B"], "eval": ["C", "D"]}
EN_LEADING_WORDS = {"send", "text", "message", "tell", "draft", "write", "start", "open", "show", "mark", "reply",
                    "add", "schedule", "put", "create", "move", "reschedule", "push", "cancel", "delete", "remove",
                    "share", "please", "to", "a", "my", "with", "on", "actually"}


def _lead_lower(u):
    first = u.split(" ", 1)[0].strip(",").lower()
    return u[0].lower() + u[1:] if first in EN_LEADING_WORDS else u


def paraphrase(family, locale, u):
    if locale == "en-US":
        return {"A": lambda: "Could you please " + _lead_lower(u),
                "B": lambda: "Hey, " + _lead_lower(u),
                "C": lambda: "I need you to " + _lead_lower(u),
                "D": lambda: u + ", thanks"}[family]()
    if family == "A":
        return u + "もらえる？" if u.endswith("て") else "すみません、" + u
    if family == "B":
        return "ねえ、" + u
    if family == "C":
        return u + "おいてほしい" if u.endswith("て") else "お願いなんだけど、" + u
    return u + "、お願い"


def build_v1_catalogs(v0):
    cats = json.loads(json.dumps(v0))
    msgs = []
    for (locale, tag), items in V1_MESSAGE_SNIPPETS.items():
        for n, (sender, text) in enumerate(items, 1):
            msgs.append({"id": f"msg_{locale[:2]}_{tag}{n}", "type": "MessageEntity", "locale": locale,
                         "forms": [form(text)], "qualifiers": [], "related": {"sender": sender}, "attrs": {}})
    cats["messages"]["entities"] += V1_CONTACTS + [conversation_for(c) for c in V1_CONTACTS] + msgs
    cats["calendar"]["entities"] += V1_EVENTS
    for c in cats.values():
        c["dataset_version"] = "v1"
    return cats


V1_BLOCKS = {"messages": [("B", "A"), ("C", "B")], "calendar": [("B", "C"), ("C", "D")]}
V1_PER_LOCALE = 300


# ---------------------------------------------------------------------------

def generate():
    rnd = random.Random(SEED)
    catalogs = build_catalogs()
    splits = {"dev": [], "eval": []}
    for app, maker in (("messages", messages_cases), ("calendar", calendar_cases)):
        for locale in ("en-US", "ja-JP"):
            cases = maker(locale, rnd, catalogs[app])
            if len(cases) != PER_LOCALE:
                raise RuntimeError(f"{app}/{locale}: expected {PER_LOCALE} cases, got {len(cases)}")
            for n, c in enumerate(cases, 1):
                c["case_id"] = f"{app}-{locale[:2]}-{n:03d}"
            splits[SPLIT_OF_APP[app]].extend(cases)
    return splits, catalogs


def generate_v1(v0_splits, v0_catalogs):
    """v1 = the v0 cases unchanged + two new 100-case blocks per (app, locale), each in one paraphrase family."""
    rnd = random.Random(SEED + 1)
    catalogs = build_v1_catalogs(v0_catalogs)
    splits = {"dev": [], "eval": []}
    for app, maker, pools in (("messages", messages_cases, MESSAGE_POOLS), ("calendar", calendar_cases, CALENDAR_POOLS)):
        split = SPLIT_OF_APP[app]
        for locale in ("en-US", "ja-JP"):
            base = [c for c in v0_splits[split] if c["locale"] == locale]
            seen = {(c["utterance"], json.dumps(c["state"], sort_keys=True, ensure_ascii=False)) for c in base}
            cases = list(base)
            for pool_id, family in V1_BLOCKS[app]:
                assert family in HOLDOUT_FAMILIES[split]
                b = Builder(app, locale, rnd, seen=seen, family=family)
                block = maker(locale, rnd, catalogs[app], pool=pools[(pool_id, locale)], b=b)
                if len(block) != PER_LOCALE:
                    raise RuntimeError(f"{app}/{locale}/{pool_id}: expected {PER_LOCALE} cases, got {len(block)}")
                cases += block
            for n, c in enumerate(cases[len(base):], len(base) + 1):
                c["case_id"] = f"{app}-{locale[:2]}-{n:03d}"
            if len(cases) != V1_PER_LOCALE:
                raise RuntimeError(f"{app}/{locale}: expected {V1_PER_LOCALE} cases, got {len(cases)}")
            splits[split].extend(cases)
    return splits, catalogs



# ---------------------------------------------------------------------------
# v1.1: cases for the data gaps found by the Phase 2 real runs (v1 stays frozen)
# ---------------------------------------------------------------------------

V11_EVENTS = [
    event("ev_maya_party", "Maya's Graduation Party", "Saturday", "2026-11-14", "17:00", qualifiers=["saturday"], calendar="cal_personal"),
    event("ev_theo_recital", "Theo's Piano Recital", "Sunday", "2026-11-15", "15:00", qualifiers=["sunday"], calendar="cal_personal"),
    event("ev_grandma_lunch", "Grandma's Birthday Lunch", "Sunday", "2026-11-22", "12:00", qualifiers=["sunday"], calendar="cal_personal"),
    event("jev_allhands", "オールハンズ・ミーティング", "木曜", "2026-11-19", "16:00", reading="おーるはんずみーてぃんぐ", qualifiers=["木曜"], locale="ja-JP"),
]
LOCATIONS = {"en-US": ["Harbor Clinic", "Northside Studio", "Elm Street Garage", "Riverside Library"],
             "ja-JP": ["みなと歯科", "北口スタジオ", "駅前整備工場", "川沿い図書館"]}
CALENDAR_MENTIONS = {"en-US": [("Work", "cal_work"), ("Personal", "cal_personal")],
                     "ja-JP": [("仕事", "cal_work"), ("プライベート", "cal_personal")]}
V11_BLOCK = {"messages": ["A", "B"], "calendar": ["C", "D"]}


def build_v11_catalogs(v1):
    cats = json.loads(json.dumps(v1))
    cats["calendar"]["entities"] += V11_EVENTS
    for c in cats.values():
        c["dataset_version"] = "v1.1"
    return cats


def v11_cases(app, locale, rnd, catalog, seen):
    """Extra cases per (app, locale): the paraphrase family alternates within the split's holdout families."""
    ents = by_id(catalog["entities"])
    en = locale == "en-US"
    fams = V11_BLOCK[app]
    builders = {f: Builder(app, locale, rnd, seen=seen, family=f, lineage="v1.1-gap") for f in fams}
    order = []

    def add(i, make, **kw):
        b = builders[fams[i % len(fams)]]
        b.add(make, **kw)
        order.append(b.cases[-1])

    if app == "calendar":
        # (1) Location-bearing create requests: the only input on which calendar_broken's remote
        #     geocoder runs, so F8 can be observed in a real run.
        tpl = (["Add {t} on {d} at {h} at {l}", "Schedule {t} for {d} at {h} at {l}"] if en else
               ["{d}の{h}に{t}を入れて、場所は{l}", "{d}{h}から{t}の予定を作って、場所は{l}"])
        for i in range(12):
            def make(tpl=tpl[i % 2], i=i):
                t, d, h = rnd.choice(NEW_TITLES[locale]), rnd.choice(DAYS[locale]), rnd.choice(TIMES[locale])
                loc = LOCATIONS[locale][i % 4]
                return tpl.format(t=t, d=d, h=h, l=loc), ex("CreateEventIntent", None, {"title": t, "day": d, "time": h, "location": loc}), {}
            add(i, make, tag="gap_location", difficulty="medium")
        # (2) Create on a calendar named by its title or alias (calendar aliases were not indexed).
        tpl = "Add {t} to my {c} calendar on {d} at {h}" if en else "{c}のカレンダーに{d}の{h}で{t}を入れて"
        for i in range(6):
            mention, cal = CALENDAR_MENTIONS[locale][i % 2]
            def make(mention=mention, cal=cal):
                t, d, h = rnd.choice(NEW_TITLES[locale]), rnd.choice(DAYS[locale]), rnd.choice(TIMES[locale])
                return tpl.format(t=t, c=mention, d=d, h=h), ex("CreateEventIntent", None, {"title": t, "day": d, "time": h, "calendar": cal}), {}
            add(i, make, tag="gap_calendar_alias", adversarial=True, difficulty="medium")
        # (3) Titles Spotlight did not return for their own text: possessives (EN) and
        #     katakana with long vowels / middle dots (JA).
        targets = (["ev_maya_party", "ev_theo_recital", "ev_grandma_lunch"] if en else ["jev_zensha", "jev_allhands", "jev_allhands"])
        acts = ([("open", "Open {e}"), ("delete", "Cancel {e}"), ("update", "Move {e} to {h}"), ("share", "Share {e} with {p}")] if en else
                [("open", "{e}を開いて"), ("delete", "{e}をキャンセルして"), ("update", "{e}を{h}に変更して"), ("share", "{e}を{p}に共有して")])
        for i in range(6):
            eid = targets[i % 3]
            action, t = acts[i % 4]
            name = spoken(ents[eid], locale) if not (eid == "jev_allhands" and i >= 3) else "オールハンズミーティング"
            def make(action=action, t=t, eid=eid, name=name):
                h, p = rnd.choice(TIMES[locale]), rnd.choice(INVITEES[locale])
                params = {"time": h} if action == "update" else ({"invitee": p} if action == "share" else {})
                return t.format(e=name, h=h, p=p), ex(CAL_INTENT[action], eid, params), {}
            add(i, make, tag="gap_title_index", adversarial=True, difficulty="medium", mention=name)
    else:
        if en:
            # (4) Conversations by nickname and by possessive.
            plan = [("Open my chat with {n}", "c_kate", 1), ("Show my conversation with {n}", "c_alex", 1),
                    ("Open my chat with {n}", "c_tomasz", 1), ("Show my conversation with {n}", "c_elena", 1),
                    ("Open my chat with {n}", "c_dmitri", 1), ("Show my conversation with {n}", "c_grace", 1),
                    ("Open {n}'s chat", "c_anjali", 1), ("Show {n}'s conversation", "c_omar", 1),
                    ("Open {n}'s chat", "c_hugo", 1), ("Show {n}'s conversation", "c_clara", 1),
                    ("Open {n}'s chat", "c_kwame", 1), ("Show {n}'s conversation", "c_felix", 1)]
        else:
            # (4) Conversations by the contact's full kana reading (conversation readings were not indexed).
            ids = ["j_takase", "j_sato", "j_ishikawa", "j_onodera", "j_fujii", "j_hirano",
                   "j_okamoto", "j_murakami", "j_hara", "j_kanno", "j_shibata", "j_matsuda"]
            plan = [("{n}とのトークを開いて" if k % 2 == 0 else "{n}との会話を見せて", cid, None) for k, cid in enumerate(ids)]
        for i, (tpl, cid, fi) in enumerate(plan):
            e = ents[cid]
            name = spoken(e, locale, fi) if fi is not None else e["forms"][0]["reading"].replace(" ", "")
            def make(tpl=tpl, cid=cid, name=name):
                return tpl.format(n=name), ex("OpenConversationIntent", "conv_" + cid, {}), {}
            add(i, make, tag="gap_conversation_index", adversarial=True, difficulty="medium", mention=name)
    return order


V11_EXTRA = {"messages": 12, "calendar": 24}


def generate_v11(v1_splits, v1_catalogs):
    rnd = random.Random(SEED + 2)
    catalogs = build_v11_catalogs(v1_catalogs)
    splits = {"dev": [], "eval": []}
    for app in ("messages", "calendar"):
        split = SPLIT_OF_APP[app]
        for locale in ("en-US", "ja-JP"):
            base = [c for c in v1_splits[split] if c["locale"] == locale]
            seen = {(c["utterance"], json.dumps(c["state"], sort_keys=True, ensure_ascii=False)) for c in base}
            extra = v11_cases(app, locale, rnd, catalogs[app], seen)
            if len(extra) != V11_EXTRA[app]:
                raise RuntimeError(f"{app}/{locale}: expected {V11_EXTRA[app]} v1.1 cases, got {len(extra)}")
            for n, c in enumerate(extra, len(base) + 1):
                c["case_id"] = f"{app}-{locale[:2]}-{n:03d}"
            splits[split].extend(base + extra)
    return splits, catalogs



V0_KEYS = ["case_id", "split", "app_id", "domain", "locale", "utterance", "noise", "state", "expected",
           "adversarial", "difficulty", "tags"]


def v0_view(c):
    return {k: c[k] for k in V0_KEYS}


def v1_view(c):
    out = v0_view(c)
    out["mention"] = c["_mention"]
    out["generator"] = c["_generator"]
    return out


def dump_jsonl(cases, view=v0_view):
    return "".join(json.dumps(view(c), ensure_ascii=False, sort_keys=False) + "\n" for c in cases)


def write_dataset(out, splits, catalogs, view):
    (out / "entities").mkdir(parents=True, exist_ok=True)
    (out / "cases_dev.jsonl").write_text(dump_jsonl(splits["dev"], view), encoding="utf-8")
    (out / "cases_eval.jsonl").write_text(dump_jsonl(splits["eval"], view), encoding="utf-8")
    for app, catalog in catalogs.items():
        (out / "entities" / f"{app}.json").write_text(json.dumps(catalog, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    total = sum(len(v) for v in splits.values())
    adv = sum(c["adversarial"] for v in splits.values() for c in v)
    print(f"wrote {total} cases (dev={len(splits['dev'])}, eval={len(splits['eval'])}, adversarial={adv / total:.0%}) to {out}")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--out", default=str(pathlib.Path(__file__).resolve().parent))
    args = parser.parse_args(argv)
    out = pathlib.Path(args.out)
    # The stages are generated in order because each builds on the previous one (same seeds);
    # only the final dataset, v1.2, is written.
    base, base_catalogs = generate()
    stage_splits, stage_catalogs = generate_v1(base, base_catalogs)
    splits, catalogs = generate_v11(stage_splits, stage_catalogs)
    for c in catalogs.values():
        c["dataset_version"] = "v1.2"
    write_dataset(out / "v1.2", splits, catalogs, v1_view)


if __name__ == "__main__":
    main()
