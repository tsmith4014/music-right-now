# import os
# import json
# import youtube_dl
# from slack_bolt import App
# from slack_bolt.adapter.aws_lambda import SlackRequestHandler
# import subprocess
# import tempfile

# app = App(signing_secret=os.environ.get("SLACK_SIGNING_SECRET"))

# channel_id = "C0717R6ND17"  # Replace with your actual channel ID

# @app.command("/play")
# def play_music(ack, respond, command):
#     ack()
#     query = command['text']
#     video_url = f"https://www.youtube.com/results?search_query={query}"

#     try:
#         info = youtube_dl.YoutubeDL({'format': 'bestaudio'}).extract_info(video_url, download=False)
#         audio_url = info['url']

#         with tempfile.NamedTemporaryFile(delete=False, suffix=".mp3") as temp_audio:
#             temp_audio.close()
#             subprocess.run(["youtube-dl", "-x", "--audio-format", "mp3", "-o", temp_audio.name, audio_url])

#             respond({
#                 "response_type": "in_channel",
#                 "text": f"Now playing: {info['title']}",
#                 "attachments": [
#                     {
#                         "text": f"<{audio_url}|Listen here>"
#                     }
#                 ]
#             })

#     except Exception as e:
#         respond(f"Failed to play music: {str(e)}")

# def handler(event, context):
#     slack_handler = SlackRequestHandler(app=app)
#     return slack_handler.handle(event, context)


import os
from slack_bolt import App
from slack_bolt.adapter.aws_lambda import SlackRequestHandler

app = App(signing_secret=os.environ.get("SLACK_SIGNING_SECRET"))

@app.command("/play")
def play_music(ack, respond, command):
    ack()
    query = command['text']
    search_url = f"https://www.youtube.com/results?search_query={query}"
    respond({
        "response_type": "in_channel",
        "text": f"Check out the search results for your query: <{search_url}|Click here>",
    })

def handler(event, context):
    slack_handler = SlackRequestHandler(app=app)
    return slack_handler.handle(event, context)