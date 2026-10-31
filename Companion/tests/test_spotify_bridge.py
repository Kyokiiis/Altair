import importlib.util
from pathlib import Path
import tempfile
import threading
import time
import unittest
from unittest.mock import patch
from urllib.parse import parse_qs, urlsplit
from urllib.request import Request, urlopen
from urllib.error import HTTPError
import json

spec=importlib.util.spec_from_file_location('bridge',Path(__file__).parents[1]/'spotify_bridge.py')
b=importlib.util.module_from_spec(spec);spec.loader.exec_module(b)

class OAuthTests(unittest.TestCase):
    def test_artwork_uses_smallest_valid_spotify_cover(self):
        item={"album":{"images":[{"url":"https://i.scdn.co/image/large","width":640},
                                  {"url":"https://i.scdn.co/image/small","width":64},
                                  {"url":"https://example.com/image/bad","width":64},
                                  {"url":"https://i.scdn.co.evil/image/bad","width":64}]}}
        self.assertEqual(b.artwork_url(item),"https://i.scdn.co/image/small")
        self.assertEqual(b.artwork_url({}),"")
        self.assertEqual(b.artwork_url({"images":[{"url":"http://127.0.0.1/private","width":64}]}),"")

    def setUp(self):
        self.temp=tempfile.TemporaryDirectory()
        self.store=b.TokenStore(Path(self.temp.name)/'tokens')
        self.media=b.WebSpotify(self.store,43827)
    def tearDown(self): self.temp.cleanup()
    def begin(self):
        with patch.object(b.webbrowser,'open') as browser:
            result=self.media.begin_link('a'*32)
            browser.assert_called_once_with(result['url'])
        return parse_qs(urlsplit(result['url']).query)
    def test_link_refresh_unlink_relink(self):
        query=self.begin()
        self.assertEqual(query['code_challenge_method'],['S256'])
        self.assertNotIn('client_secret',query)
        with patch.object(self.media,'exchange',return_value={'access_token':'test-access','refresh_token':'test-refresh','expires_in':3600}) as exchange:
            self.media.finish_link({'state':query['state'],'code':['test-code']})
            self.assertIn('code_verifier',exchange.call_args.args[0])
        self.assertTrue(self.media.snapshot()['linked'])
        self.assertEqual(self.store.load()['refresh_token'],'test-refresh')
        if b.os.name=='nt': self.assertNotIn(b'test-refresh',self.store.path.read_bytes())
        self.media.tokens['expires_at']=0
        with patch.object(self.media,'exchange',return_value={'access_token':'refreshed','expires_in':3600}):
            self.assertEqual(self.media.access_token(),'refreshed')
        self.assertEqual(self.media.tokens['refresh_token'],'test-refresh')
        self.media.unlink()
        self.assertFalse(self.store.path.exists());self.assertFalse(self.media.snapshot()['linked'])
        with self.assertRaises(ValueError): self.media.access_token()
        self.assertNotEqual(query['state'],self.begin()['state'])
    def test_invalid_expired_replayed_callback(self):
        query=self.begin()
        with self.assertRaises(ValueError): self.media.finish_link({'state':['wrong'],'code':['x']})
        self.media.pending['expires']=0
        with self.assertRaises(ValueError): self.media.finish_link({'state':query['state'],'code':['x']})
        query=self.begin()
        with self.assertRaises(ValueError): self.media.finish_link({'state':query['state'],'error':['access_denied']})
        self.assertIsNone(self.media.pending)
        with self.assertRaises(ValueError): self.media.finish_link({'state':query['state'],'code':['x']})
    def test_playback_controls_and_numeric_validation(self):
        self.media.state={'connected':True,'playing':True,'progress':10,'duration':100}
        self.media.sampled_at=time.monotonic()-2
        with patch.object(self.media,'api') as api:
            self.media.dispatch('toggle',None)
            self.assertFalse(self.media.state['playing']);self.assertGreaterEqual(self.media.state['progress'],12)
            self.media.dispatch('seek',999);self.assertEqual(self.media.state['progress'],100)
            self.media.dispatch('volume',-1);self.assertEqual(self.media.state['volume'],0)
            for value in [True,float('nan'),float('inf'),'1']:
                with self.assertRaises(ValueError): self.media.dispatch('seek',value)
            self.media.dispatch('next',None)
            self.assertEqual(api.call_args.args,('POST','me/player/next'))
    def test_invalid_client_id(self):
        with self.assertRaises(ValueError): self.media.begin_link('secret')
    def test_companion_restart_preserves_link_and_refresh_token(self):
        self.store.save({'access_token':'old','refresh_token':'saved-refresh','client_id':'a'*32,'expires_at':0})
        restarted=b.WebSpotify(self.store,43827)
        self.assertTrue(restarted.snapshot()['linked'])
        with patch.object(restarted,'exchange',return_value={'access_token':'renewed','expires_in':3600}):
            self.assertEqual(restarted.access_token(),'renewed')
        again=b.WebSpotify(self.store,43827)
        self.assertEqual(again.tokens['refresh_token'],'saved-refresh')
        self.assertTrue(again.snapshot()['linked'])
    def test_failure_backoff_recovers(self):
        self.media.tokens={'access_token':'test'}
        with patch.object(b.time,'monotonic',return_value=100),patch.object(self.media,'api',side_effect=ValueError('Retry later')):
            self.media.refresh_state()
        with patch.object(b.time,'monotonic',return_value=102),patch.object(self.media,'api') as api:
            self.media.refresh_state();api.assert_not_called()
        with patch.object(b.time,'monotonic',return_value=106),patch.object(self.media,'api',return_value=None) as api:
            self.media.refresh_state();api.assert_called_once()
        self.assertTrue(self.media.snapshot()['connected'])
    def test_nullable_playback_and_restricted_device(self):
        self.media.tokens={'access_token':'test'}
        data={'item':None,'progress_ms':None,'device':{'volume_percent':None,'supports_volume':False},
              'actions':{'disallows':{'skipping_next':True,'seeking':True}}}
        with patch.object(self.media,'api',return_value=data): self.media.refresh_state()
        state=self.media.snapshot()
        self.assertEqual(state['progress'],0);self.assertEqual(state['volume'],0)
        self.assertFalse(state['controls']['volume']);self.assertFalse(state['controls']['next'])
        self.assertFalse(state['controls']['seek'])
    def test_successful_controls_accept_empty_or_text_acknowledgments(self):
        from unittest.mock import MagicMock
        self.media.tokens={'access_token':'test','expires_at':time.time()+3600}
        for body in [b'',b' ',b'OK']:
            response=MagicMock();response.status=200;response.read.return_value=body
            response.__enter__.return_value=response
            with patch.object(b,'urlopen',return_value=response):
                self.assertIsNone(self.media.api('PUT','me/player/pause'))

class HTTPTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory()
        self.media=b.WebSpotify(b.TokenStore(Path(self.temp.name)/'tokens'),43827)
        self.server=b.Server(0,self.media,'k'*43)
        self.thread=threading.Thread(target=self.server.serve_forever,daemon=True);self.thread.start()
        self.url=f'http://127.0.0.1:{self.server.server_address[1]}'
    def tearDown(self):
        self.server.shutdown();self.server.server_close();self.temp.cleanup()
    def request(self,path,data=None,headers=None):
        request=Request(self.url+path,data=json.dumps(data).encode() if data is not None else None,
                        headers=headers or {'Authorization':'Bearer '+'k'*43,'Content-Type':'application/json'})
        try:
            with urlopen(request,timeout=3) as response: return response.status,json.load(response)
        except HTTPError as response: return response.code,json.load(response)
    def test_auth_origin_and_routes(self):
        self.assertEqual(self.request('/v1/state')[0],200)
        self.assertEqual(self.request('/v1/state',headers={'Authorization':'wrong'})[0],401)
        self.assertEqual(self.request('/v1/state',headers={'Authorization':'Bearer '+'k'*43,'Origin':'https://example.com'})[0],403)
        self.assertEqual(self.request('/missing')[0],404)
        self.assertEqual(self.request('/v1/control',{'action':'execute'})[0],400)
        self.assertEqual(self.request('/v1/unlink',{})[0],200)
        self.assertFalse(self.media.snapshot()['linked'])
    def test_link_does_not_expose_tokens(self):
        with patch.object(b.webbrowser,'open'):
            status,body=self.request('/v1/link',{'clientId':'a'*32})
        self.assertEqual(status,200);self.assertNotIn('token',json.dumps(body))
        self.assertEqual(self.request('/callback?state=wrong&code=x')[0],400)

if __name__=='__main__': unittest.main()
