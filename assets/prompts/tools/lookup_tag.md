查某个 tag / 角色 / 作品是什么意思（不含画师）:
  query: tag 或中文关键词
  category: 可选，"character" / "copyright" / "general" / "meta"
  limit: 返回上限，默认 10
何时调:
  - 仅当: 用户在问某个名字或 tag 是什么
  - 禁止: 画图时调用；角色没查到就按用户原话写
返回: tag、zh（中文名）、category、post_count（热度）；wiki 是释义，可能是英文，转述给用户时说中文；为空就如实说查不到
