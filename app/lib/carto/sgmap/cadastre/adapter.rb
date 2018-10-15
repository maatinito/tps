class CARTO::SGMAP::Cadastre::Adapter
  def initialize(coordinates)
    @coordinates = GeojsonService.to_json_polygon_for_cadastre(coordinates)
  end

  def data_source
    @data_source ||= JSON.parse(CARTO::SGMAP::API.search_cadastre(@coordinates), symbolize_names: true)
  end

  def to_params
    data_source[:features].map do |feature|
      filter_properties(feature[:properties]).merge({ geometry: feature[:geometry] })
    end
  end

  def filter_properties(properties)
    properties.slice(
      :surface_intersection,
      :surface_parcelle,
      :numero,
      :feuille,
      :section,
      :code_dep,
      :nom_com,
      :code_com,
      :code_arr
    )
  end
end
