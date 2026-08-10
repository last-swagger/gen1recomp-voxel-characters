-- Faz o LOVE reportar erro por stdout e SAIR, em vez de abrir janela e esperar.
--
-- Todo driver deste diretorio comeca chamando isto. Por padrao o LOVE trata
-- erro abrindo uma tela com a mensagem e esperando tecla; de dentro de um
-- script isso e indistinguivel de trabalho pesado, e a ferramenta so morre no
-- timeout, com log vazio, enquanto a causa fica escrita numa janela que ninguem
-- esta olhando. Tres vezes numa sessao.
--
-- A alternativa que eu tentei antes, fotografar a tela para ler a mensagem, foi
-- pior: numa maquina de trabalho a foto pega o que estiver na frente, e pegou
-- conversa pessoal duas vezes. As imagens foram apagadas e a ideia abandonada.
-- A mensagem tem que sair por onde o script ja le.
return function()
  local function handler(msg)
    msg = tostring(msg)
    io.stdout:write("ERRO DE LOVE: " .. msg .. "\n")
    io.stdout:write(debug.traceback("", 2) .. "\n")
    io.stdout:flush()
    os.exit(1)
  end
  love.errorhandler = handler
  love.errhand = handler
end
