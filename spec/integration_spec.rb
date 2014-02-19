require 'spec_helper'

shared_examples 'something fabricatable' do
  subject { fabricated_object }
  let(:fabricated_object) { Fabricate(fabricator_name, placeholder: 'dynamic content') }

  context 'defaults from fabricator' do
    its(:dynamic_field) { should == 'dynamic content' }
    its(:nil_field) { should be_nil }
    its(:number_field) { should == 5 }
    its(:string_field) { should == 'content' }
    its(:false_field) { should == false }
  end

  context 'model callbacks are fired' do
    its(:before_save_value) { should == 11 }
  end

  context 'overriding at fabricate time' do
    let(:fabricated_object) do
      Fabricate(
        "#{fabricator_name}_with_children",
        string_field: 'new content',
        number_field: 10,
        nil_field: nil,
        placeholder: 'is not invoked'
      ) do
        dynamic_field { 'new dynamic content' }
      end
    end

    its(:dynamic_field) { should == 'new dynamic content' }
    its(:nil_field) { should be_nil }
    its(:number_field) { should == 10 }
    its(:string_field) { should == 'new content' }

    context 'child collections' do
      subject { fabricated_object.send(collection_field) }
      its(:size) { should == 2 }
      its(:first) { should be_persisted }
      its("first.number_field") { should == 10 }
      its(:last) { should be_persisted }
      its("last.number_field") { should == 10 }
    end
  end

  context 'state of the object' do
    it 'generates a fresh object every time' do
      Fabricate(fabricator_name).should_not == subject
    end
    it { should be_persisted }
  end

  context 'transient attributes' do
    it { should_not respond_to(:placeholder) }
    its(:extra_fields) { should == { transient_value: 'dynamic content' } }
  end

  context 'build' do
    subject { Fabricate.build("#{fabricator_name}_with_children") }
    it { should_not be_persisted }

    it 'cascades to child records' do
      subject.send(collection_field).each do |o|
        o.should_not be_persisted
      end
    end
  end

  context 'attributes for' do
    subject { Fabricate.attributes_for(fabricator_name) }
    it { should be_kind_of(Fabrication::Support.hash_class) }
    it 'serializes the attributes' do
      should include({
        :dynamic_field => nil,
        :nil_field => nil,
        :number_field => 5,
        :string_field => 'content'
      })
    end
  end

  context 'belongs_to associations' do
    subject { Fabricate("#{Fabrication::Support.singularize(collection_field.to_s)}_with_parent") }

    it 'sets the parent association' do
      subject.send(fabricator_name).should be
    end

    it 'sets the id of the associated object' do
      subject.send("#{fabricator_name}_id").should == subject.send(fabricator_name).id
    end
  end
end

describe Fabrication do

  context 'plain old ruby objects' do
    let(:fabricator_name) { :parent_ruby_object }
    let(:collection_field) { :child_ruby_objects }
    it_should_behave_like 'something fabricatable'
  end

  context 'active_record models', depends_on: :active_record do
    let(:fabricator_name) { :parent_active_record_model }
    let(:collection_field) { :child_active_record_models }
    it_should_behave_like 'something fabricatable'

    context 'associations in attributes_for' do
      let(:parent_model) { Fabricate(:parent_active_record_model) }
      subject do
        Fabricate.attributes_for(:child_active_record_model, parent_active_record_model: parent_model)
      end

      it 'serializes the belongs_to as an id' do
        should include({ parent_active_record_model_id: parent_model.id })
      end
    end

    context 'association proxies' do
      subject { parent_model.child_active_record_models.build }
      let(:parent_model) { Fabricate(:parent_active_record_model_with_children) }
      it { should be_kind_of(ChildActiveRecordModel) }
    end
  end

  context 'data_mapper models', depends_on: :data_mapper do
    let(:fabricator_name) { :parent_data_mapper_model }
    let(:collection_field) { :child_data_mapper_models }

    it_should_behave_like 'something fabricatable'

    context 'associations in attributes_for' do
      let(:parent_model) { Fabricate(:parent_data_mapper_model) }
      subject do
        Fabricate.attributes_for(
          :child_data_mapper_model, parent_data_mapper_model: parent_model
        )
      end

      it 'serializes the belongs_to as an id' do
        should include({ parent_data_mapper_model_id: parent_model.id })
      end
    end
  end

  context 'referenced mongoid documents', depends_on: :mongoid do
    let(:fabricator_name) { :parent_mongoid_document }
    let(:collection_field) { :referenced_mongoid_documents }
    it_should_behave_like 'something fabricatable'
  end

  context 'embedded mongoid documents', depends_on: :mongoid do
    let(:fabricator_name) { :parent_mongoid_document }
    let(:collection_field) { :embedded_mongoid_documents }
    it_should_behave_like 'something fabricatable'
  end

  context 'sequel models', depends_on: :sequel do
    let(:fabricator_name) { :parent_sequel_model }
    let(:collection_field) { :child_sequel_models }
    it_should_behave_like 'something fabricatable'

    context 'with class table inheritance' do
      before do
        Fabricate(:sequel_knight)
        Fabricate(:sequel_farmer)
        Fabricate(:sequel_knight)
      end

      it 'generates the right number of objects' do
        SequelFarmer.count.should == 3
        SequelKnight.count.should == 2
      end
    end
  end

  context 'when the class requires a constructor' do
    subject do
      Fabricate(:city) do
        on_init { init_with('Jacksonville Beach', 'FL') }
      end
    end

    its(:city)  { should == 'Jacksonville Beach' }
    its(:state) { should == 'FL' }
  end

  context 'with a class in a module' do
    subject { Fabricate("Something::Amazing", :stuff => "things") }
    its(:stuff) { should == "things" }
  end

  context 'with the generation parameter' do

    let(:person) do
      Fabricate(:person, :first_name => "Paul") do
        last_name { |attrs| "#{attrs[:first_name]}#{attrs[:age]}" }
        age 50
      end
    end

    it 'evaluates the fields in order of declaration' do
      person.last_name.should == "Paul"
    end

  end

  context 'with a field named the same as an Object method' do
    subject { Fabricate(:predefined_namespaced_class, display: 'working') }
    its(:display) { should == 'working' }
  end

  context 'multiple instance' do

    let(:person1) { Fabricate(:person, :first_name => 'Jane') }
    let(:person2) { Fabricate(:person, :first_name => 'John') }

    it 'person1 is named Jane' do
      person1.first_name.should == 'Jane'
    end

    it 'person2 is named John' do
      person2.first_name.should == 'John'
    end

    it 'they have different last names' do
      person1.last_name.should_not == person2.last_name
    end

  end

  context 'with a specified class name' do

    let(:someone) { Fabricate(:someone) }

    before do
      Fabricator(:someone, :class_name => :person) do
        first_name "Paul"
      end
    end

    it 'generates the person as someone' do
      someone.first_name.should == "Paul"
    end

  end

  context 'for namespaced classes' do
    context 'the namespaced class' do
      subject { Fabricate('namespaced_classes/ruby_object', name: 'working') }
      its(:name) { should eq('working') }
      it { should be_a(NamespacedClasses::RubyObject) }
    end

    context 'descendant from namespaced class' do
      subject { Fabricate(:predefined_namespaced_class) }
      its(:name) { should eq('aaa') }
      it { should be_a(NamespacedClasses::RubyObject) }
    end
  end

  context 'with a mongoid document', depends_on: :mongoid do
    let(:author) { Fabricate(:author) }

    it "sets the author name" do
      author.name.should == "George Orwell"
    end

    it 'generates four books' do
      author.books.map(&:title).should == (1..4).map { |i| "book title #{i}" }
    end

    it "sets dynamic fields" do
      Fabricate(:special_author).mongoid_dynamic_field.should == 50
    end

    it "sets lazy dynamic fields" do
      Fabricate(:special_author).lazy_dynamic_field.should == "foo"
    end

    context "with disabled dynamic fields" do
      it "raises NoMethodError for mongoid_dynamic_field=" do
        if Mongoid.respond_to?(:allow_dynamic_fields=)
          Mongoid.allow_dynamic_fields = false
          expect { Fabricate(:special_author) }.to raise_error(Mongoid::Errors::UnknownAttribute, /mongoid_dynamic_field=/)
          Mongoid.allow_dynamic_fields = true
        end
      end
    end
  end

  context 'with multiple callbacks' do
    let(:child) { Fabricate(:child) }

    it "runs the first callback" do
      child.first_name.should == "Johnny"
    end

    it "runs the second callback" do
      child.age.should == 10
    end
  end

  context 'with multiple, inherited callbacks' do
    let(:senior) { Fabricate(:senior) }

    it "runs the parent callbacks first" do
      senior.age.should == 70
    end
  end

  describe '.clear_definitions' do
    before { Fabrication.clear_definitions }
    after { Fabrication::Support.find_definitions }

    it 'should not generate authors' do
      Fabrication.manager[:author].should be_nil
    end
  end

  context 'when defining a fabricator twice' do
    it 'throws an error' do
      lambda { Fabricator(:parent_ruby_object) {} }.should raise_error(Fabrication::DuplicateFabricatorError)
    end
  end

  context "when defining a fabricator for a class that doesn't exist" do
    it 'throws an error' do
      lambda { Fabricator(:class_that_does_not_exist) }.should raise_error(Fabrication::UnfabricatableError)
    end
  end

  context 'when generating from a non-existant fabricator' do
    it 'throws an error' do
      lambda { Fabricate(:misspelled_fabricator_name) }.should raise_error(Fabrication::UnknownFabricatorError)
    end
  end

  context 'defining a fabricator' do
    context 'without a block' do
      before(:all) do
        class Widget; end
        Fabricator(:widget)
      end

      it 'works fine' do
        Fabricate(:widget).should be
      end
    end

    context 'for a non-existant class' do
      it "raises an error if the class cannot be located" do
        lambda { Fabricator(:somenonexistantclass) }.should raise_error(Fabrication::UnfabricatableError)
      end
    end
  end

  describe "Fabricate with a sequence" do
    subject { Fabricate(:sequencer) }

    its(:simple_iterator) { should == 0 }
    its(:param_iterator)  { should == 10 }
    its(:block_iterator)  { should == "block2" }

    context "when namespaced" do
      subject { Fabricate("Sequencer::Namespaced") }

      its(:iterator) { should == 0 }
    end
  end

  describe 'Fabricating while initializing' do
    before { Fabrication.manager.preinitialize }
    after { Fabrication.manager.freeze }

    it 'throws an error' do
      lambda { Fabricate(:your_mom) }.should raise_error(Fabrication::MisplacedFabricateError)
    end
  end

  describe 'using an actual class in options' do
    subject { Fabricate(:actual_class) }

    context 'from' do
      before do
        Fabricator(:actual_class, from: OpenStruct) do
          name 'Hashrocket'
        end
      end
      after { Fabrication.clear_definitions }
      its(:name) { should == 'Hashrocket' }
      it { should be_kind_of(OpenStruct) }
    end

    context 'class_name' do
      before do
        Fabricator(:actual_class, class_name: OpenStruct) do
          name 'Hashrocket'
        end
      end
      after { Fabrication.clear_definitions }
      its(:name) { should == 'Hashrocket' }
      it { should be_kind_of(OpenStruct) }
    end
  end

end
