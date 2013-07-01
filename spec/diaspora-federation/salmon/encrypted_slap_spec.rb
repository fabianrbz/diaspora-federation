require 'spec_helper'

describe Salmon::EncryptedSlap do
  let(:author_id) { 'user_test@diaspora.example.tld' }
  let(:pkey) { OpenSSL::PKey::RSA.generate(512) } # use small key for speedy specs
  let(:okey) { OpenSSL::PKey::RSA.generate(1024) } # use small key for speedy specs
  let(:entity) { Entities::TestEntity.new(test: 'qwertzuiop') }
  let(:slap_xml) { Salmon::EncryptedSlap.to_xml(author_id, pkey, entity, okey.public_key) }

  context '::to_xml' do
    context 'sanity' do
      it 'accepts correct params' do
        expect {
          Salmon::EncryptedSlap.to_xml(author_id, pkey, entity, okey.public_key)
        }.not_to raise_error
      end

      it 'raises an error when the params are the wrong type' do
        ['asdf', 12345, true, :symbol, entity, pkey].each do |val|
          expect { Salmon::EncryptedSlap.to_xml(val, val, val, val) }.to raise_error
        end
      end
    end

    it 'generates valid xml' do
      doc = Ox.parse(slap_xml)
      doc.locate('diaspora').should have(1).item
      doc.locate('diaspora/encrypted_header').should have(1).item
      doc.locate('diaspora/encrypted_header').first.text.should_not be_empty
      doc.locate('diaspora/me:env').should have(1).item
    end

    context 'header' do
      subject { Ox.parse(slap_xml).locate('diaspora/encrypted_header').first.text }
      let(:cipher_header) { JSON.parse(Base64.decode64(subject)) }
      let(:header_key) {
        JSON.parse(okey.private_decrypt(Base64.decode64(cipher_header['aes_key'])))
      }

      it 'encoded the header correctly' do
        json_header = {}
        expect {
          json_header = JSON.parse(Base64.decode64(subject))
        }.not_to raise_error
        json_header.should include('aes_key', 'ciphertext')
      end

      it 'encrypted the public_key encrypted header correctly' do
        key = {}
        expect {
          key = JSON.parse(okey.private_decrypt(Base64.decode64(cipher_header['aes_key'])))
        }.not_to raise_error
        key.should include('key', 'iv')
      end

      it 'encrypted the aes encrypted header correctly' do
        header = ""
        expect {
          header = Salmon.aes_decrypt(cipher_header['ciphertext'],
                                      header_key['key'],
                                      header_key['iv'])
        }.not_to raise_error
        header_doc = Ox.parse(header)
        header_doc.name.should eql('decrypted_header')
        header_doc.locate('iv').should have(1).item
        header_doc.locate('aes_key').should have(1).item
        header_doc.locate('author_id').should have(1).item
        header_doc.locate('author_id').first.text.should eql(author_id)
      end
    end
  end

  context '::from_xml' do
    context 'sanity' do
      it 'accepts correct params' do
        expect { Salmon::EncryptedSlap.from_xml(slap_xml, okey) }.not_to raise_error
      end

      it 'raises an error when the params have a wrong type' do
        [12345, false, :symbol, entity, pkey].each do |val|
          expect { Salmon::EncryptedSlap.from_xml(val, val) }.to raise_error
        end
      end

      it 'verifies the existence of "encrypted_header"' do
        faulty_xml = <<XML
<diaspora>
</diaspora>
XML
        expect {
          Salmon::EncryptedSlap.from_xml(faulty_xml, okey)
        }.to raise_error Salmon::EncryptedSlap::MissingHeader
      end

      it 'verifies the existence of a magic envelope' do
        faulty_xml = <<XML
<diaspora>
  <encrypted_header/>
</diaspora>
XML
        Salmon::EncryptedSlap.stub(:header_data).and_return({aes_key: '', iv: '', author_id: ''})
        expect {
          Salmon::EncryptedSlap.from_xml(faulty_xml, okey)
        }.to raise_error Salmon::MissingMagicEnvelope
      end
    end

    context 'generated instance' do
      subject { Salmon::EncryptedSlap.from_xml(slap_xml, okey) }

      its(:cipher_params) { should_not be_nil }

      it_behaves_like "a Slap instance"
    end
  end
end
