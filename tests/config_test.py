import pathlib
import unittest
import yaml

ROOT = pathlib.Path(__file__).resolve().parents[1]


class ConfigTests(unittest.TestCase):
    def test_undo_components_registered_before_managers(self):
        schema = yaml.safe_load((ROOT / 'xmjd6.schema.yaml').read_text(encoding='utf-8-sig'))
        processors = schema['engine']['processors']
        self.assertEqual(processors[0], 'lua_processor@*xmjd6/typing_stats_processor')
        self.assertLess(processors.index('lua_processor@*xmjd6/undo_processor'),
                        processors.index('lua_processor@*xmjd6/dynamic_phrase_processor'))
        self.assertIn('lua_translator@*xmjd6/undo_translator', schema['engine']['translators'])

    def test_streaming_template_does_not_remove_processors_by_position(self):
        custom = (ROOT / 'xmjd6.custom.yaml').read_text()
        self.assertNotIn('engine/processors/@', custom)
        self.assertIn('topup/enabled: false', custom)
        schema = yaml.safe_load((ROOT / 'xmjd6.schema.yaml').read_text(encoding='utf-8-sig'))
        self.assertTrue(schema['topup']['enabled'])

    def test_runtime_module_refs_exist(self):
        schema = yaml.safe_load((ROOT / 'xmjd6.schema.yaml').read_text(encoding='utf-8-sig'))
        for component in ('processors', 'translators', 'filters'):
            for name in schema['engine'][component]:
                if '@*' in name:
                    module = name.split('@*', 1)[1].split('@', 1)[0]
                    self.assertTrue((ROOT / 'lua' / (module + '.lua')).is_file(), module)


if __name__ == '__main__':
    unittest.main()
