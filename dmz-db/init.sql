-- Banco do Hotel Vale Verde (ficticio).
-- Todos os dados abaixo sao FICTICIOS e existem apenas para o laboratorio.
-- Este script roda uma unica vez, na primeira criacao do volume "dbdata".
-- No hotel, a "reserva" liga o hospede a um quarto; o "consumo" e o que ele
-- gastou na conta.

CREATE TABLE hospedes (
    id       SERIAL PRIMARY KEY,
    nome     TEXT NOT NULL,
    telefone TEXT
);

CREATE TABLE reservas (
    id         SERIAL PRIMARY KEY,
    quarto     TEXT NOT NULL,
    tipo       TEXT NOT NULL,
    hospede_id INTEGER NOT NULL REFERENCES hospedes(id)
);

CREATE TABLE checkins (
    id         SERIAL PRIMARY KEY,
    reserva_id INTEGER NOT NULL REFERENCES reservas(id),
    data_hora  TIMESTAMP NOT NULL
);

CREATE TABLE consumos (
    id         SERIAL PRIMARY KEY,
    reserva_id INTEGER NOT NULL REFERENCES reservas(id),
    descricao  TEXT NOT NULL,
    valor      NUMERIC(8,2) NOT NULL
);

INSERT INTO hospedes (nome, telefone) VALUES
    ('Hospede Exemplo 1', '(00) 00000-0001'),
    ('Hospede Exemplo 2', '(00) 00000-0002'),
    ('Hospede Exemplo 3', '(00) 00000-0003');

INSERT INTO reservas (quarto, tipo, hospede_id) VALUES
    ('101', 'solteiro', 1),
    ('202', 'casal', 2),
    ('303', 'suite', 3);

INSERT INTO checkins (reserva_id, data_hora) VALUES
    (1, '2026-10-20 14:00'),
    (2, '2026-10-20 15:00'),
    (3, '2026-10-21 16:30');

INSERT INTO consumos (reserva_id, descricao, valor) VALUES
    (1, 'Frigobar', 35.50),
    (2, 'Jantar', 120.00),
    (3, 'Lavanderia', 48.90);