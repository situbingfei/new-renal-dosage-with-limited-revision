-- Initial schema and data snapshot generated from renal_dose_database.json.
-- Current source snapshot: 59 dose-rule rows, 0 QR links. Text values are preserved as text.
-- Run only for a NEW Supabase project. If your project already has these tables/data,
-- do not rerun this seed; run supabase-admin-rls-migration.sql only.
-- This script deliberately does not change Supabase-managed storage.objects.
begin;

create table if not exists public.drug_rules (
  _id text primary key,
  drug_id text not null,
  drug_name text not null,
  renal_function_level text not null default '',
  ccr_min text not null default '',
  ccr_max text not null default '',
  dose_unit text not null default '',
  dose_value text not null default '',
  dose_total_value text not null default '',
  dose_description text not null default '',
  adjustment_rule text not null default '',
  special_notes text not null default '',
  reference text not null default '',
  sort_order integer not null default 0
);

create table if not exists public.drug_qr (
  drug_id text not null,
  drug_name text not null,
  storage_path text not null,
  original_name text not null default '',
  updated_at timestamptz not null default now(),
  primary key (drug_id, drug_name)
);

insert into public.drug_rules ("_id", drug_id, drug_name, renal_function_level, ccr_min, ccr_max, dose_unit, dose_value, dose_total_value, dose_description, adjustment_rule, special_notes, reference, sort_order)
values
  ('32ae44659199431895b03a80104026e3', 'cisplatin', '顺铂', '肾功能正常', '60', '999', 'mg/m²', '75', '', '75 mg/m²', '肌酐清除率>60ml/min，建议以75mg/m²给药', '无', '药品说明书', 0),
  ('a9bce755a66447039bd272a688c42e44', 'cisplatin', '顺铂', '轻度肾功能不全', '40', '59', 'mg/m²', '60', '', '60 mg/m²', '肌酐清除率40-59ml/min，建议初始剂量减少25%', '无', '药品说明书', 1),
  ('3c88158b0fdc49ae832e468b911f32a1', 'cisplatin', '顺铂', '中度肾功能不全', '20', '39', 'mg/m²', '50', '', '50 mg/m²', '肌酐清除率20-39ml/min，建议剂量减少50%', '无', '药品说明书', 2),
  ('ced29232923647e385a84c2ab486db07', 'cisplatin', '顺铂', '重度肾功能不全', '15', '19', 'mg/m²', '30', '', '30 mg/m²', '肌酐清除率15-19ml/min，建议剂量减少70%', '密切监测肾功能', '药品说明书', 3),
  ('35e4736a3239488ba99ecde021cd4f31', 'cisplatin', '顺铂', '肾衰竭', '0', '14', 'string', '', '', '避免使用', '肌酐清除率≤14ml/min，禁忌使用', '肾功能衰竭患者禁用', '药品说明书', 4),
  ('55d5d784d16748f0a5beae666707a008', 'oxaliplatin', '奥沙利铂', '肾功能正常', '60', '999', 'mg/m²', '75', '', '75 mg/m²', '肾功能正常患者，建议以75mg/m²给药', '无', '药品说明书', 5),
  ('7229340c9b7348419a8acdfb54f05a3f', 'erlotinib', '厄洛替尼', '肾功能正常', '60', '999', 'mg/d', '150', '', '150 mg/d', '肾功能正常患者，建议150mg/日', '无', '药品说明书', 6),
  ('a35e7e638c7b436182c01acc5577260b', 'gefitinib', '吉非替尼', '肾功能正常', '60', '999', 'mg/d', '250', '', '250 mg/d', '肾功能正常患者，建议250mg/日', '无', '药品说明书', 7),
  ('fe1a963c582f49f38499696cf0813d17', 'fosaprepitant dimeglumine', '福沙匹坦双葡甲胺', '肾功能正常', '60', '999', '', '', '', '', '', '无', '药品说明书', 8),
  ('08733ace0a2e4ffcbbd9843b295f2d71', 'Arsenious Acid and Sodium Chloride', '亚砷酸氯化钠', '肾功能正常', '60', '999', 'mg/m²', '7', '', '7mg/m²', '肾功能正常患者，建议7mg/m²', '无', '药品说明书', 9),
  ('2eb4edb873774fff9cbba5325afd19a5', 'Draatumumba', '达雷妥尤单抗', '肾功能正常', '60', '999', 'mg/kg', '16', '', '16mg/kg', '肾功能正常患者，建议16mg/kg给药', '无', '药品说明书', 10),
  ('3703892b59764413b25a11741362268b', 'nedaplatin', '奈达铂', '肾功能正常', '60', '999', 'mg/m²', '80-100', '', '80-100mg/m²', '肾功能正常患者，建议80-100mg/m²给药', '严重肾功能不全者禁用', '药品说明书', 11),
  ('58df2d5acb2b4cc795c8548d20f6185c', 'calcium folinate', '亚叶酸钙', '肾功能正常', '60', '999', 'mg/m²', '9-15', '', '9-15mg/m²', '肾功能正常患者，建议9-15mg/m²给药', '无', '药品说明书', 12),
  ('e008af307b984bdfbebbf792234886bd', 'irinotecan hydrochloride', '盐酸伊立替康（瑞之伊）', '肾功能正常', '60', '999', 'mg/m²', '125', '', '125mg/m²', '肾功能正常患者，建议125mg/m²给药', '密切监测肾功能', '药品说明书', 13),
  ('bd55e959a41642fd960e1bada59c28d6', 'fluorouracil', '氟尿嘧啶', '', '', '', 'mg/m²', '300-500', '', '300-500mg/m²', '', '', '药品说明书', 14),
  ('c4375bc7fd4848a6bd029d0f3c3829db', 'raltitrexed', '雷替曲塞', '肾功能正常', '66', '999', 'mg/m²', '3', '', '3mg/m²', '肌酐清除率>65ml/min，建议以3mg/m²给药', '无', '药品说明书', 15),
  ('fadeb66ad3e246378482a29b80473846', 'raltitrexed', '雷替曲塞', '', '55', '65', 'mg/m²', '2', '', '2.25mg/m²', '肌酐清除率55-65ml/min，建议初始剂量减少25%', '无', '药品说明书', 16),
  ('721d05461e1649889c807fae0c40bec7', 'raltitrexed', '雷替曲塞', '', '25', '54', 'mg/m²', '2', '', '1.50mg/m²', '肌酐清除率25-54ml/min，建议初始剂量减少50%', '密切监测肾功能', '药品说明书', 17),
  ('bed1ccd78ba844fd8cab45a276e432b1', 'raltitrexed', '雷替曲塞', '', '0', '24', 'mg/m²', '', '', '避免使用', '肌酐清除率≤25ml/min，禁忌使用', '严重肾功能不全者禁用', '药品说明书', 18),
  ('f79c0117708f4f5dbd8db3a702cfddb6', 'lobaplatin', '洛铂', '肾功能正常', '60', '999', 'mg/m²', '50', '', '50 mg/m²', '肾功能正常患者，建议50mg/m²给药', '有肾功能损害患者禁用', '药品说明书', 19),
  ('cc602ec45fe1449c8a014efbaf40c683', 'utidelone', '代替德隆', '肾功能正常', '60', '999', 'mg/m²', '30', '', '30mg/m²', '肾功能正常患者，建议以30mg/m²给药', '无', '药品说明书', 20),
  ('5a405f6bd270471290afee51ebd05d5a', 'decitabine', '地西他滨', '肾功能正常', '60', '999', 'mg/m²', '15', '', '15mg/m²', '肾功能正常患者，建议15mg/m²给药', '重度肾功能损害者（CrCl＜30ml/min），需密切监测肾功能', '药品说明书', 21),
  ('19f9e73cf046436789abaf9991dba71b', 'gemcitabine', '吉西他滨（健择）', '肾功能正常', '60', '999', 'mg/m²', '1000', '', '1000mg/m²', '肾功能正常患者，建议1000mg/m²给药', '肾功能损伤患者慎用', '药品说明书', 22),
  ('572032fc40a242aba9b842d51f139023', 'doxorubicin liposome', '多柔比星脂质体', '肾功能正常', '60', '999', 'mg/m²', '20', '', '20mg/m²', '肾功能正常患者，建议20mg/m²给药', '无', '药品说明书', 23),
  ('20bf96dc883f472fa8b5dc0a264aa9b3', 'gemcitabine', '吉西他滨（泽非）', '肾功能正常', '60', '999', 'mg/m²', '1000', '', '1000mg/m²', '肾功能正常患者，建议1000mg/m²给药', '肾功能损伤患者慎用', '药品说明书', 24),
  ('677738448e6e4b87918d64d5d22a581b', 'disitamab vedotin', '维迪西妥单抗', '肾功能正常', '60', '999', '', '', '', '', '', '', '药品说明书', 25),
  ('e4a350077e6d4dfd998da1b46cb72b16', 'pemetrexed disodium', '培美曲塞二钠', '肾功能正常', '45', '999', 'mg/m²', '500', '', '500mg/m²', '肌酐清除率≥45ml/min，建议以500mg/m²给药', '无', '药品说明书', 26),
  ('7544a6ca31f44230af7fb718461e8c6d', 'pemetrexed disodium', '培美曲塞二钠', '', '0', '44', 'mg/m²', '', '', '避免使用', '肌酐清除率＜45ml/min，不推荐使用', '无', '药品说明书', 27),
  ('430e543451ab4ecc9071db1a8c167c14', 'carboplatin', '卡铂', '', '60', '999', 'mg/m²', '300-400', '', '300-400mg/m²', '肌酐清除率>60ml/min，建议以300-400mg/m²给药', '无', '药品说明书', 28),
  ('0152447bfba54b8496485e01fe6e76da', 'carboplatin', '卡铂', '', '0', '59', 'mg/m²', '', '', '减量使用', '肌酐清除率＜60ml/min，建议减量使用', '无', '药品说明书', 29),
  ('60ec4b4727854aadb4509ae78bfd8d92', 'rituximab', '利妥昔单抗', '肾功能正常', '60', '999', 'mg/m²', '375', '', '375mg/m²', '肾功能正常患者，建议375mg/m²给药', '无', '药品说明书', 30),
  ('40aeaa68f7904cd29d9c4b97b54beb75', 'inetetamab', '伊尼妥单抗', '', '', '', 'mg/kg', '4', '', '', '', '', '', 31),
  ('cc01f72c7e1a4869af0da63f43f3602b', 'cetuximab solution', '西妥昔单抗', '肾功能正常', '60', '999', 'mg/m²', '400', '', '400mg/m²', '肾功能正常患者，建议400mg/m²给药', '无', '药品说明书', 32),
  ('d16af75ec77744c3ba34762ea0ff05c2', 'tocilizumab', '托珠单抗', '肾功能正常', '60', '999', 'mg/kg', '8', '', '8mg/kg', '肾功能正常与轻度肾功能损伤患者，建议8mg/kg给药', '无', '药品说明书', 33),
  ('d7f859b8e9f44b47adf18faf052de156', 'trastuzumab emtansine', '恩美曲妥珠单抗', '肾功能正常', '90', '999', 'mg/kg', '4', '', '3.6mg/kg', '肾功能正常患者，建议3.6mg/kg给药', '无', '药品说明书', 34),
  ('1bc0104dd6db4fa697c8ebf5d565c257', 'trastuzumab emtansine', '恩美曲妥珠单抗', '轻度肾功能不全', '60', '89', 'mg/kg', '4', '', '3.6mg/kg', '肌酐清除率60-89ml/min，建议以3.6mg/kg给药', '无', '药品说明书', 35),
  ('2f937c5f57094bd1b4a0da7394741a55', 'trastuzumab emtansine', '恩美曲妥珠单抗', '中度肾功能不全', '30', '59', 'mg/kg', '4', '', '3.6mg/kg', '肌酐清除率30-59ml/min，建议以3.6mg/kg给药', '无', '药品说明书', 36),
  ('bc969b57c0144196bd735de60ec77c6d', 'trastuzumab emtansine', '恩美曲妥珠单抗', '重度肾功能不全', '15', '29', 'mg/kg', '', '', '', '肌酐清除率15-29ml/min，数据有限，无法提供给药剂量建议', '无', '药品说明书', 37),
  ('98418a55124f496b980f430e9c7411c0', 'obinutuzumab', '奥妥珠单抗', '肾功能正常', '90', '999', 'mg', '1000', '', '1000mg', '肾功能正常患者，建议1000mg给药', '无', '药品说明书', 38),
  ('f2c4db603fe744839f723466ac263e1d', 'obinutuzumab', '奥妥珠单抗', '轻度肾功能不全', '50', '89', 'mg', '1000', '', '1000mg', '肌酐清除率50-89ml/min，建议以1000mg给药', '无', '药品说明书', 39),
  ('7dd07d1fad1f4d85b338e97b77172bfe', 'obinutuzumab', '奥妥珠单抗', '中度肾功能不全', '30', '49', 'mg', '1000', '', '1000mg', '肌酐清除率30-49ml/min，建议以1000mg给药', '无', '药品说明书', 40),
  ('292c499b39ad45daad3df19101fe563e', 'obinutuzumab', '奥妥珠单抗', '重度肾功能不全', '15', '29', 'mg', '', '', '', '肌酐清除率15-29ml/min，数据有限，无法提供给药剂量建议', '无', '药品说明书', 41),
  ('e6c2c0cae4d444cd90b0a6ed7ae3010b', 'trastuzumab', '曲妥珠单抗', '', '', '', 'mg/kg', '4', '', '400mg/kg', '', '', '药品说明书', 42),
  ('83e8cda67bfc4f3394f12b7cbb13c36c', 'infliximab', '英夫利西单抗', '', '', '', 'mg/kg', '', '', 'mg/kg', '', '', '药品说明书', 43),
  ('4c7ddc04128e4d439011a7d539f966f7', 'pertuzumab', '帕妥珠单抗', '肾功能正常', '60', '999', 'mg', '840', '', '840mg', '肾功能正常患者，建议840mg起始剂量给药，此后每三周给药一次，给药剂量为420mg', '无', '药品说明书', 44),
  ('3dac6de83ed54fd38dae54efe60381bf', 'bevacizumab', '贝伐珠单抗', '肾功能正常', '60', '999', '', '', '', '', '', '无', '药品说明书', 45),
  ('3f577c27350b4ad698a303d963494900', 'nimotuzumab', '尼妥珠单抗', '', '', '', '', '', '', '', '', '', '药品说明书', 46),
  ('7bc935a2dd9949e8a932909a21e890c6', 'carfilzomib', '卡非佐米', '', '', '', '', '', '', '', '', '', '药品说明书', 47),
  ('043f4d08f4d348199b77ef872d853001', 'ifosfamide', '异环磷酰胺', '', '', '', 'g/m²', '1.2-2.5', '', '1.2-2.5g/m²', '', '', '药品说明书', 48),
  ('88a50155c47540bc93faec1e64648baa', 'methotrexate', '甲氨蝶呤', '', '', '', 'mg  ;  mg/m²', '10-50mg ; 20-30mg/m²', '', '成人一次10-50mg；儿童每日20-30mg/m²', '', '', '药品说明书', 49),
  ('3bbdad32c9a94321bf5c47a724e167d2', 'paclitaxel', '紫杉醇注射液', '', '', '', '', '', '', '', '', '', '药品说明书', 50),
  ('583e20ebbf934ecd8527322f8c48c372', 'irinotecan hydrochloride', '伊立替康(开普拓）', '肾功能正常', '60', '999', 'mg/m²', '125', '', '125mg/m²', '肾功能正常患者，建议125mg/m²给药', '密切监测肾功能', '药品说明书', 51),
  ('d19790593d654695a8ccc7e116a9e357', 'cyclophosphamide', '注射用环磷酰胺', '', '', '', '', '', '', '', '', '', '药品说明书', 52),
  ('b5fad04ea7784e2597ee38c468004282', 'tislelizumab', '替雷利珠单抗', '', '', '', '', '', '', '', '', '重度肾功能不全不推荐使用', '药品说明书', 53),
  ('8cafc05976c4477fa5bb9be25069edd3', 'ivonescimab', '依沃西单抗', '轻度肾功能不全', '60', '90', 'mg/kg', '20', '', '20mg/m²', '轻度 60≤CLCr≤90或中度 30≤CLCr≤60肾功能不全患者无需进行剂量调整', '无', '药品说明书', 54),
  ('ca27371d8d964ebcabd7836128524d4a', 'ivonescimab', '依沃西单抗', '中度肾功能不全', '30', '60', 'mg/kg', '20', '', '20mg/m²', '轻度 60≤CLCr≤90或中度 30≤CLCr≤60肾功能不全患者无需进行剂量调整', '无', '药品说明书', 55),
  ('518e08b074ef4017826f7b01c5ca8a84', 'sintilimab', '信迪利单抗', '肾功能正常', '60', '999', 'mg', '200', '', '200mg', '肾功能正常、轻度肾功能损伤中度肾功能损伤患者，建议200mg给药', '重度肾功能不全患者慎用', '药品说明书', 56),
  ('abed912ee2384b00ace854bd30dfbe06', 'toripalimab', '特瑞普利单抗', '', '', '', '', '', '', '', '', '轻度和中度肾功能损伤患者慎用，重度肾功能损伤患者不推荐使用', '药品说明书', 57),
  ('00dbc192823a48a8b13b87699fd48e73', 'camrelizumab', '卡瑞利珠单抗', '肾功能正常', '60', '999', 'mg', '200', '', '200mg', '肾功能正常、轻度肾功能损伤患者，建议200mg给药', '中度和重度肾功能损伤患者不推荐使用', '药品说明书', 58)
on conflict (_id) do nothing;

commit;
