// 文件职责：PostCSS 配置，仅注册 @tailwindcss/postcss 插件。
// 分层：网站构建配置；样式入口只经 Tailwind，不引入其他 PostCSS 插件。
export default {
  plugins: {
    "@tailwindcss/postcss": {},
  },
};
