"""Evidence integrity tests, independent of model answer quality."""
import copy
import json
import tempfile
import unittest
from pathlib import Path

import provenance
import score


class EvidenceIntegrityTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = Path(self.directory.name)
        self.addCleanup(self.directory.cleanup)
        self.suite_sha = '1' * 64

    def run_files(self, name='dev', case='example.dev', split='dev'):
        folder = self.root / name
        folder.mkdir()
        row = dict(caseID=case, model='qwen35', kind='prose', split=split, effort='standard', repeatIndex=0,
                   prompt='Prepared prompt', responseGrammar=None, baselinePrompts=True, context=4096, batch=512)
        repo, revision, filename, size, model_sha = provenance.MODEL_PINS['qwen35']
        metadata = dict(complete=True, suiteSHA256=self.suite_sha, executableSHA256='2' * 64,
                        sourceSHA256={'main.swift': '3' * 64}, runtimeFilesSHA256={'lib/libllama.so': '4' * 64},
                        swiftVersion='Swift6.4', platform='Linux CPU', processor='Test CPU', logicalProcessors=12,
                        runtime=dict(runtimeBuild=provenance.RUNTIME_PINS['BUILD'],
                                     sourceSHA256=provenance.RUNTIME_PINS['SOURCE_SHA256'],
                                     sourceURL=provenance.RUNTIME_PINS['SOURCE_URL'],
                                     librarySHA256='4' * 64, installedFilesSHA256={'lib/libllama.so': '4' * 64}),
                        models=[dict(model='qwen35',repository=repo,revision=revision,filename=filename,bytes=size,
                                     sha256=model_sha,url=f'https://huggingface.co/{repo}/resolve/{revision}/{filename}',verified=True)],
                        settings={field:'declared' for field in provenance.INFERENCE_FIELDS},
                        promptSHA256={'qwen35':[dict(caseID=case,effort='standard',repeatIndex=0,prompt=provenance.sha(row['prompt']),replyPrompt=None)]},
                        responseGrammarSHA256={'qwen35':[dict(caseID=case,effort='standard',repeatIndex=0,sha256=None)]})
        metadata['settings'].update(context=4096,batch=512,backend='Linux CPU',split=split,baselinePrompts=True,efforts='standard',repeats=1)
        self.write(folder/'rows.jsonl', row, jsonl=True)
        self.write(folder/'metadata.json', metadata)
        return folder

    @staticmethod
    def write(path, value, jsonl=False):
        path.write_text(json.dumps(value)+('\n' if jsonl else ''),encoding='utf-8')

    def manifest(self, folders):
        entries = [dict(rows=str((folder/'rows.jsonl').relative_to(self.root)),
                        rowsSHA256=provenance.sha((folder/'rows.jsonl').read_bytes()),
                        metadata=str((folder/'metadata.json').relative_to(self.root)),
                        metadataSHA256=provenance.sha((folder/'metadata.json').read_bytes())) for folder in folders]
        path=self.root/'collection.json'
        self.write(path,dict(formatVersion=1,streams=entries))
        return path

    def verify(self, folders):
        return provenance.verify_run_manifest(self.manifest(folders),[folder/'rows.jsonl' for folder in folders],self.suite_sha)

    def test_disjoint_complete_batches_share_execution_identity(self):
        dev=self.run_files()
        heldout=self.run_files('heldout','example.heldout','heldout')
        result=self.verify([dev,heldout])
        self.assertEqual('verified',result['status'])
        self.assertEqual(2,len(result['streams']))

    def test_stream_tampering_cannot_be_hidden_by_scoring_same_keys(self):
        folder=self.run_files()
        manifest=self.manifest([folder])
        with (folder/'rows.jsonl').open('a',encoding='utf-8') as out:
            out.write('\n')
        with self.assertRaisesRegex(ValueError,'stream hash mismatch'):
            provenance.verify_run_manifest(manifest,[folder/'rows.jsonl'],self.suite_sha)

    def test_updated_stream_digest_does_not_hide_prompt_tampering(self):
        folder=self.run_files()
        row=json.loads((folder/'rows.jsonl').read_text())
        row['prompt']='Different prepared prompt'
        self.write(folder/'rows.jsonl',row,True)
        with self.assertRaisesRegex(ValueError,'prepared prompt hash mismatch'):
            self.verify([folder])

    def test_updated_metadata_digest_does_not_permit_mixed_binary(self):
        dev=self.run_files()
        heldout=self.run_files('heldout','example.heldout','heldout')
        metadata=json.loads((heldout/'metadata.json').read_text())
        metadata['executableSHA256']='5'*64
        self.write(heldout/'metadata.json',metadata)
        with self.assertRaisesRegex(ValueError,'mixed source/executable'):
            self.verify([dev,heldout])

    def test_complete_flag_and_pin_fields_are_required(self):
        for field,value,message in [('complete',False,'incomplete'),('suiteSHA256','9'*64,'fixture hash')]:
            with self.subTest(field=field):
                folder=self.run_files(field)
                metadata=json.loads((folder/'metadata.json').read_text())
                metadata[field]=value
                self.write(folder/'metadata.json',metadata)
                with self.assertRaisesRegex(ValueError,message): self.verify([folder])
        folder=self.run_files('unpinned')
        metadata=json.loads((folder/'metadata.json').read_text())
        metadata['models'][0]['sha256']='9'*64
        self.write(folder/'metadata.json',metadata)
        with self.assertRaisesRegex(ValueError,'model asset pin mismatch'): self.verify([folder])

    def test_manifest_must_bind_exact_scored_stream_set(self):
        dev=self.run_files()
        heldout=self.run_files('heldout','example.heldout','heldout')
        with self.assertRaisesRegex(ValueError,'exactly the scored streams'):
            provenance.verify_run_manifest(self.manifest([dev]),[dev/'rows.jsonl',heldout/'rows.jsonl'],self.suite_sha)

    def test_grammar_hash_cannot_be_changed_even_when_stream_digest_changes(self):
        folder=self.run_files()
        row=json.loads((folder/'rows.jsonl').read_text())
        row['responseGrammar']='root ::= "changed"'
        self.write(folder/'rows.jsonl',row,True)
        with self.assertRaisesRegex(ValueError,'response grammar hash mismatch'): self.verify([folder])

    def test_paired_pipeline_source_can_differ_but_runtime_and_budgets_cannot(self):
        folder=self.run_files()
        before=self.verify([folder])['identity']
        after=copy.deepcopy(before)
        after['executableSHA256']='5'*64
        after['sourceSHA256']={'main.swift':'6'*64}
        after['inferenceSettings'].update(baselinePrompts=False,grammarPolicy='new',repeats=3)
        self.assertTrue(provenance.paired_identity_matches(before,after))
        after['runtimeFilesSHA256']['lib/libllama.so']='7'*64
        self.assertFalse(provenance.paired_identity_matches(before,after))

    def test_no_manifest_keeps_partial_dev_scoreable_and_release_blocked(self):
        suite=dict(id='test',version=1,models=['qwen35'],cases=[])
        report=score.make_report(suite,self.suite_sha,[],scope='dev')
        self.assertIn('run_provenance_not_verified',report['releaseGate']['reasons'])

    def test_combined_baseline477_pairs_final525_without_promoting_repeats(self):
        suite=json.loads((Path(__file__).with_name('harbour-model-quality-v1.json')).read_text(encoding='utf-8'))
        efforts=['quick','standard','extended']
        dev=score.expected_keys([c for c in suite['cases'] if c['split']=='dev'],suite['models'],efforts,1)
        heldout=score.expected_keys([c for c in suite['cases'] if c['split']=='heldout'],suite['models'],efforts,1)
        final=score.expected_keys(suite['cases'],suite['models'],efforts,3)
        self.assertEqual((267,210,0),(len(dev),len(heldout),len(dev&heldout)))
        self.assertEqual(477,len(dev|heldout))
        self.assertEqual(dev|heldout,{k for k in final if k[3]==0})
        self.assertEqual(48,len(final-(dev|heldout)))

    def test_six_disjoint_streams_pair_primary_results_and_reject_overlap(self):
        fixture=dict(id='dev.list',split='dev',kind='routing',language='en',input='List medicines',
                     expected=dict(tool='list_medications'),effortSubset=True,timingSubset=True)
        heldout=copy.deepcopy(fixture)
        heldout.update(id='heldout.list',split='heldout')
        suite=dict(id='paired-test',version=1,models=['small','balanced','qwen35'],cases=[fixture,heldout])
        efforts=['quick','standard','extended']
        paths=[]
        for model in suite['models']:
            for case in suite['cases']:
                rows=[dict(model=model,caseID=case['id'],kind='routing',split=case['split'],language='en',
                           effort=effort,repeatIndex=0,output='selected',observedTool='list_medications',
                           finalTool='list_medications',validationSucceeded=True,actionSummary=dict(type='list_medications')) for effort in efforts]
                path=self.root/f"{model}-{case['split']}.jsonl"
                path.write_text('\n'.join(json.dumps(row) for row in rows)+'\n',encoding='utf-8')
                paths.append(path)
        combined=score.read_rows(paths)
        baseline=score.make_report(suite,self.suite_sha,combined,efforts=efforts)
        self.assertEqual([],baseline['matrix']['missing'])
        self.assertEqual([],baseline['matrix']['duplicates'])
        final=combined+[dict(row,repeatIndex=repeat) for row in combined if row['effort']=='standard' for repeat in (1,2)]
        report=score.make_report(suite,self.suite_sha,final,efforts=efforts,repeats=3,baseline=baseline)
        self.assertEqual([],report['comparison']['missingPairs'])
        self.assertEqual([],report['matrix']['missing'])
        self.assertEqual(18,len([r for r in report['results'] if r['repeatIndex']==0]))
        overlap=score.make_report(suite,self.suite_sha,combined+combined[:1],efforts=efforts)
        self.assertEqual(1,len(overlap['matrix']['duplicates']))
        self.assertIn('incomplete_or_mismatched_matrix',overlap['releaseGate']['reasons'])


if __name__ == '__main__':
    unittest.main()
