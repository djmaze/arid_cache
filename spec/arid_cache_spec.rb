require File.expand_path(File.dirname(__FILE__) + '/spec_helper')

describe "AridCache" do
  describe 'order' do
    before :each do
      @company1 = Company.make(:name => 'a')
      @company2 = Company.make(:name => 'b')
      Company.class_caches do
        ordered_by_name { Company.all(:order => 'name ASC') }
      end
      #Company.clear_caches
    end

    it "should keep the original order with no order option" do
      results = Company.cached_ordered_by_name
      results.size.should == 2
      results[0].name.should == @company1.name
      results[1].name.should == @company2.name
    end

    it "should match the order option" do
      results = Company.cached_ordered_by_name(:order => 'name DESC')
      results.size.should == 2
      results[0].name.should == @company2.name
      results[1].name.should == @company1.name
    end
  end
end
