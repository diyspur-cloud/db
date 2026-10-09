# Verity — proveniência da ficha do catálogo

Registro de fontes usadas para a edição brasileira cadastrada no DIYSPUR. Valores temporais/de preço não voláteis foram separados da ficha editorial; preço não foi armazenado.

| Dado | Valor cadastrado | Fonte |
|---|---|---|
| Título / autora | *Verity* — Colleen Hoover | [Página oficial da autora](https://www.colleenhoover.com/products/verity) |
| ISBN-13 | 9788501117847 | [Editora Record](https://www.record.com.br/produto/verity/) |
| Selo editorial | Galera Record | [Casa Vamos Ler — ficha pelo ISBN](https://www.casavamosler.com.br/livro/hoo010/9788501117847/verity.html) |
| Tradução | Thaís Britto | [Editora Record](https://www.record.com.br/produto/verity/) |
| Lançamento no Brasil | 9 de março de 2020 | [Editora Record](https://www.record.com.br/produto/verity/) |
| Páginas | 320 | [Editora Record](https://www.record.com.br/produto/verity/) |
| Edição / formato | 22ª edição, capa comum | [Casa Vamos Ler — ficha pelo ISBN](https://www.casavamosler.com.br/livro/hoo010/9788501117847/verity.html) (fonte livreira secundária) |
| Dimensões | 135 × 210 × 17 mm | [Editora Record](https://www.record.com.br/produto/verity/) |
| Classificação indicativa | 18 anos | [Editora Record](https://www.record.com.br/produto/verity/) |
| Gênero/editorial | Thriller romântico independente; suspense psicológico | [Autora](https://www.colleenhoover.com/products/verity) e [Editora Record](https://www.record.com.br/produto/verity/) |
| Capa | URL oficial da imagem usada em `cover_url` | [CDN da Editora Record](https://www.record.com.br/cdn/shop/files/d714a333a0c7d64404774020856088c2.jpg?v=1791572393) |
| Quantidade de capítulos | 25 capítulos da narrativa principal; seções do manuscrito interno não contadas | [Resenha independente](https://atravesdoslivros.com.br/2020/11/07/resenha-verity-colleen-hoover/) (contagem secundária, não informada pela editora) |
| Vídeos do clube | Capítulos 1–3 | URLs fornecidos pelo usuário: [1](https://youtu.be/zyJkEg09nbo), [2](https://youtu.be/RQKB4AdTEKc), [3](https://youtu.be/WThFSwoxpc8) |

A sinopse cadastrada é uma paráfrase sem spoilers baseada nas sinopses da editora e da autora. Classificação e atributos da edição brasileira não foram inferidos da edição em inglês da Hachette, que corresponde a outro ISBN/formato.

## Escopo técnico

A migration `20261009194650_add_verity_edition_metadata_and_catalog.sql` adiciona colunas tipadas para editora, tradutor, data, classificação, número de edição, formato e dimensões; substitui o registro/ciclo de demonstração anterior; mantém a janela 8 out.–12 nov. 2026, ativa, às 20:00; e cria os três registros iniciais de capítulo. O app exibe os metadados na ficha `/livros/verity`.
